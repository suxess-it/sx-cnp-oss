# Backup

Overview how identity and access management works in our platform, at first, how initial setup will work:

## High-Level Overview

Keycloak is beeing installed via Helm Charts.
User and Credentials Configuration are currently served via Helm values file (ESO is on the roadmap) [see default values files](https://github.com/suxess-it/sx-cnp-oss/tree/main/platform-apps/charts/keycloak):

User are configured via __groups__:
- __admins__: adminusers with admin entitlement
- __users__: "normal" user entitlement
- __team1__: "team" group entitlement

2FA with mobile Authenticator is added for users and team1

Extend Groups/Users to your needs

Github or other Identity Providers can be added to Keycloak, if neccessary
- only __1__ github provider possible

## Customizing Metrics
tbd
