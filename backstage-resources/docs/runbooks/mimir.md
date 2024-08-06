In this document are some runbooks for different problems listet.

## per-user series limit of 150000 exceeded (err-mimir-max-series-per-user)

When ingesting prometheus metrics to mimir you get the error `per-user series limit of 150000 exceeded (err-mimir-max-series-per-user)`.
Mimir has a configured limit of time series of 150k. This is on purpose because a higher number of time series could decrease performance and memory usage.
So before increasing the configured limit, you should take a look if your high series count is really needed.

Follow the steps in https://medium.com/@dotdc/how-to-find-unused-prometheus-metrics-using-mimirtool-a44560173543 to get all used and unused metrics in your environment.
Then follow https://medium.com/@dotdc/prometheus-performance-and-cardinality-in-practice-74d5d9cd6230 to drop unused metrics.










### old documentation - DRAFT

1. Download mimirtool from [Grafana Website](https://grafana.com/docs/mimir/latest/manage/tools/mimirtool/#installation)
2. Create a Grafana API-Token (Roles 'Viewer') or get one from your Grafana system administrator
3. Get all used metrics in Grafana with this command:
```
$ mimirtool analyze grafana --address=<Grafana-URL> --key="<API-Key from step 2>"
```
A `metrics-in-grafana.json` file should get writte in your current directory.




references:

- https://github.com/suxess-it/sx-cnp-oss/issues/380
