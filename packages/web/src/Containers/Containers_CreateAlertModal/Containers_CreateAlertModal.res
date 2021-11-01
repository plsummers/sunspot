module Mutation_CreateAlertRule = %graphql(`
  mutation CreateAlertRuleInput($input: CreateAlertRuleInput!) {
    alertRule: createAlertRule(input: $input) {
      id 
      contractAddress
      accountAddress
      collectionSlug
      destination {
        ... on WebPushAlertDestination {
          endpoint
        }
        ...on DiscordAlertDestination {
          endpoint
        }
      }
      eventFilters {
        ... on AlertPriceThresholdEventFilter {
          value
          direction
          paymentToken {
            id
          }
        }
        ... on AlertAttributesEventFilter {
          attributes {
            ... on OpenSeaAssetNumberAttribute {
              traitType
              numberValue: value
            }
            ... on OpenSeaAssetStringAttribute {
              traitType
              stringValue: value
            }
          }
        }
      }
    }
  }
`)

@react.component
let make = (~isOpen, ~onClose, ~accountAddress=?) => {
  let (createAlertRuleMutation, createAlertRuleMutationResult) = Mutation_CreateAlertRule.use()
  let (value, setValue) = React.useState(() => AlertModal.Value.empty())

  let handleExited = () => {
    setValue(_ => AlertModal.Value.empty())
  }

  let handleCreate = () => {
    let _ = switch (value->AlertModal.Value.collection, accountAddress) {
    | (Some(collection), Some(accountAddress)) =>
      Services.PushNotification.getSubscription()
      |> Js.Promise.then_(subscription => {
        switch subscription {
        | Some(subscription) => Js.Promise.resolve(subscription)
        | None => Services.PushNotification.subscribe()
        }
      })
      |> Js.Promise.then_(pushSubscription => {
        open Mutation_CreateAlertRule

        let eventFilters =
          value
          ->AlertModal.Value.rules
          ->Belt.Map.String.valuesToArray
          ->Belt.Array.keepMap(rule => {
            let direction = switch CreateAlertRule.Price.modifier(rule) {
            | ">" => Some(#ALERT_ABOVE)
            | "<" => Some(#ALERT_BELOW)
            | _ => None
            }
            let value =
              rule
              ->CreateAlertRule.Price.value
              ->Belt.Option.map(value =>
                value->Services.PaymentToken.formatPrice(Services.PaymentToken.ethPaymentToken)
              )

            switch (direction, value) {
            | (Some(direction), Some(value)) =>
              Some({
                alertPriceThresholdEventFilter: Some({
                  direction: direction,
                  value: value,
                  paymentToken: {
                    id: Services.PaymentToken.id(Services.PaymentToken.ethPaymentToken),
                    decimals: Services.PaymentToken.decimals(Services.PaymentToken.ethPaymentToken),
                    name: Services.PaymentToken.name(Services.PaymentToken.ethPaymentToken),
                    symbol: Services.PaymentToken.symbol(Services.PaymentToken.ethPaymentToken),
                  },
                }),
                alertAttributesEventFilter: None,
              })
            | _ => None
            }
          })

        let destination = {
          open Externals.ServiceWorkerGlobalScope.PushSubscription
          let s = getSerialized(pushSubscription)

          {
            webPushAlertDestination: Some({
              endpoint: s->endpoint,
              keys: {
                p256dh: s->keys->p256dh,
                auth: s->keys->auth,
              },
            }),
            discordAlertDestination: None,
          }
        }
        let input = {
          id: AlertModal.Value.id(value),
          accountAddress: accountAddress,
          collectionSlug: AlertModal.CollectionOption.slugGet(collection),
          contractAddress: AlertModal.CollectionOption.contractAddressGet(collection),
          eventFilters: eventFilters,
          destination: destination,
        }

        createAlertRuleMutation({
          input: input,
        }) |> Js.Promise.then_(_result => {
          onClose()
          Js.Promise.resolve()
        })
      })
    | _ => Js.Promise.resolve()
    }
  }

  let isCreating = switch createAlertRuleMutationResult {
  | {loading: true} => true
  | _ => false
  }

  <AlertModal
    isOpen
    onClose
    onExited={handleExited}
    value={value}
    onChange={newValue => setValue(_ => newValue)}
    isActioning={isCreating}
    onAction={handleCreate}
    actionLabel="create"
    title="create alert"
  />
}
