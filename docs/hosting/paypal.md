# PayPal — enrichir les libellés de transactions (Sure)

Sure peut remplacer les libellés génériques du type **PAYPAL…** (souvent seulement dans les **notes** de l’écriture importée) par le libellé renvoyé par l’**API Transaction Search** de PayPal, en rapprochant **montant** et **date** (fenêtre de ±2 jours).

## Prérequis

1. Compte [PayPal Developer](https://developer.paypal.com/) et application **REST** (type approprié pour votre usage).
2. Activer les produits / autorisations nécessaires pour l’**accès à l’historique des transactions** (Transaction Search / reporting). Les détails exacts évoluent selon le tableau PayPal : suivez la doc officielle pour votre type de compte.
3. **URI de redirection** : enregistrez exactement l’URL de callback de Sure, sans différence de casse ni de slash final :

   `https://<votre-domaine>/accounts/<ID_COMPTE>/paypal_oauth_callback`

   Remplacez `<votre-domaine>` par l’hôte public de votre instance et notez que l’**ID** du compte Sure est celui du **compte bancaire** sur lequel apparaissent les transactions PayPal.

4. **Scopes OAuth** utilisés par Sure (voir code : `Paypal::ApiClient::SEARCH_SCOPE`) : notamment l’accès en lecture à la recherche de transactions PayPal.

## Configuration dans Sure

1. Ouvrez **Comptes** → le compte concerné → **Modifier**.
2. Sous **Détails supplémentaires**, ouvrez la section **PayPal**.
3. Choisissez **Production** ou **Sandbox**, renseignez **Client ID** et **Secret**, puis **Enregistrez** le compte.
4. Cliquez sur **Connecter le compte PayPal** et acceptez l’autorisation sur PayPal.

## Utilisation

- Les **notes** de l’écriture doivent contenir **`PAYP`** (insensible à la casse), par ex. `PAYPAL *…` comme sur un relevé.
- Sur la liste des transactions ou dans la fiche, le bouton **PayPal** apparaît si le compte a PayPal connecté et que vous avez les droits **propriétaire / contrôle total**.
- Sure interroge PayPal sur une plage de dates autour de l’écriture et choisit l’activité dont le **montant** (devise du compte) correspond le mieux.

## Limites importantes

- L’API **Transaction Search** est orientée **activité PayPal** (soldes marchands / historique côté PayPal). Selon votre type de compte PayPal et les droits de l’application, certaines activités **personnelles** peuvent être **absentes** ou **incomplètes**. Dans ce cas, aucune correspondance n’est trouvée.
- Ne commitez **jamais** le secret dans le dépôt ; il est stocké chiffré côté application lorsque le chiffrement Active Record est configuré (comme pour les autres secrets du projet).

## Dépannage

- **token_exchange_failed** : vérifiez que l’URI de redirection dans l’app PayPal est **strictement** la même que celle générée par Sure pour ce compte.
- **no_match** : vérifiez la devise du compte, le montant exact (frais / change) et la date ; élargissez manuellement la fenêtre n’est pas possible depuis l’UI (contribution bienvenue).
