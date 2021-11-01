module Query_AlertRulesByAccountAddress = %graphql(`
  query AlertRulesByAccountAddress($accountAddress: String!, $limit: Int, $nextToken: String) {
    alertRules: alertRulesByAccountAddress(accountAddress: $accountAddress, limit: $limit, nextToken: $nextToken) {
      items {
        id
        collection {
          slug
          name
          imageUrl
          contractAddress
        }
        eventFilters {
          ... on AlertPriceThresholdEventFilter {
            value
            direction
            paymentToken {
              id
              decimals
            }
          }
        }
      }
      nextToken
    }
  }
`)

type updateAlertModalState =
  | UpdateAlertModalOpen(AlertModal.Value.t)
  | UpdateAlertModalClosed

@react.component
let make = () => {
  let {eth}: Contexts.Eth.t = React.useContext(Contexts.Eth.context)
  let {signIn, authentication}: Contexts.Auth.t = React.useContext(Contexts.Auth.context)
  let query = Query_AlertRulesByAccountAddress.use(
    ~skip=switch authentication {
    | Authenticated(_) => false
    | _ => true
    },
    switch authentication {
    | Authenticated({jwt: {accountAddress}}) => {
        accountAddress: accountAddress,
        limit: Some(32),
        nextToken: None,
      }
    | _ => {accountAddress: "", limit: None, nextToken: None}
    },
  )
  let (createAlertModalIsOpen, setCreateAlertModalIsOpen) = React.useState(_ => false)
  let (updateAlertModal, setUpdateAlertModal) = React.useState(_ => UpdateAlertModalClosed)

  let queryItems = switch query {
  | {data: Some({alertRules: Some({items: Some(items)})})} =>
    items->Belt.Array.keepMap(item => item)
  | _ => []
  }
  let tableRows = queryItems->Belt.Array.map(item => {
    AlertsTable.id: item.id,
    collectionName: item.collection.name,
    collectionSlug: item.collection.slug,
    collectionImageUrl: item.collection.imageUrl,
    event: "list",
    rule: item.eventFilters
    ->Belt.Array.get(0)
    ->Belt.Option.flatMap(eventFilter =>
      switch eventFilter {
      | #AlertPriceThresholdEventFilter(eventFilter) =>
        let modifier = switch eventFilter.direction {
        | #ALERT_ABOVE => ">"
        | #ALERT_BELOW => "<"
        | #FutureAddedValue(v) => v
        }
        let formattedPrice =
          Services.PaymentToken.parsePrice(eventFilter.value, eventFilter.paymentToken.decimals)
          ->Belt.Option.map(Belt.Float.toString)
          ->Belt.Option.getExn

        Some({AlertsTable.modifier: modifier, price: formattedPrice})
      | #FutureAddedValue(_) => None
      }
    ),
  })

  let handleConnectWalletClicked = _ => {
    let _ = signIn()
  }
  let handleRowClick = row =>
    queryItems
    ->Belt.Array.getBy(item => AlertsTable.id(row) == item.id)
    ->Belt.Option.forEach(item => {
      let rules =
        item.eventFilters
        ->Belt.Array.getBy(eventFilter =>
          switch eventFilter {
          | #AlertPriceThresholdEventFilter(_) => true
          | _ => false
          }
        )
        ->Belt.Option.flatMap(eventFilter =>
          switch eventFilter {
          | #AlertPriceThresholdEventFilter(eventFilter) =>
            CreateAlertRule.Price.makeRule(
              ~id="alert-rule-price",
              ~modifier=switch eventFilter.direction {
              | #ALERT_ABOVE => ">"
              | #ALERT_BELOW => "<"
              | #FutureAddedValue(v) => v
              },
              ~value=Services.PaymentToken.parsePrice(
                eventFilter.value,
                eventFilter.paymentToken.decimals,
              )->Belt.Option.map(Belt.Float.toString),
            )->Js.Option.some
          | _ => None
          }
        )
        ->Belt.Option.map(priceRule =>
          Belt.Map.String.fromArray([(priceRule->CreateAlertRule.Price.id, priceRule)])
        )
        ->Belt.Option.getWithDefault(Belt.Map.String.empty)

      let alertModalValue = AlertModal.Value.make(
        ~collection=Some(
          AlertModal.CollectionOption.make(
            ~name=item.collection.name,
            ~slug=item.collection.slug,
            ~imageUrl=item.collection.imageUrl,
            ~contractAddress=item.collection.contractAddress,
          ),
        ),
        ~rules,
        ~id=item.id,
      )

      setUpdateAlertModal(_ => UpdateAlertModalOpen(alertModalValue))
    })

  <>
    <AlertsHeader
      eth
      onConnectWalletClicked={handleConnectWalletClicked}
      onWalletButtonClicked={handleConnectWalletClicked}
      onCreateAlertClicked={_ => setCreateAlertModalIsOpen(_ => true)}
      authenticationChallengeRequired={switch authentication {
      | AuthenticationChallengeRequired => true
      | _ => false
      }}
    />
    <Containers.CreateAlertModal
      isOpen={createAlertModalIsOpen}
      onClose={_ => setCreateAlertModalIsOpen(_ => false)}
      accountAddress=?{switch authentication {
      | Authenticated({jwt: {accountAddress}}) => Some(accountAddress)
      | _ => None
      }}
    />
    <Containers.UpdateAlertModal
      isOpen={switch updateAlertModal {
      | UpdateAlertModalOpen(_) => true
      | _ => false
      }}
      value=?{switch updateAlertModal {
      | UpdateAlertModalOpen(v) => Some(v)
      | _ => None
      }}
      onClose={_ => setUpdateAlertModal(_ => UpdateAlertModalClosed)}
      accountAddress=?{switch authentication {
      | Authenticated({jwt: {accountAddress}}) => Some(accountAddress)
      | _ => None
      }}
    />
    <AlertsTable rows={tableRows} onRowClick={handleRowClick} />
  </>
}
