## Getting started

The bash script in [scripts](scripts/manage_exp.sh) automates experiment deployment. In more detail, it:

- Parses input parameters to allow different experiment configurations.
- It builds the [NDN firmware](../fw) in the respective respective configuration. It is expected that the `arm-none-eabi-gcc` cross-compiler is installed on your machine.
- If the script is not explicitly called with an experiment ID (EXPID), it submits a new experiment on the saclay site of the testbed. It is expected that a user account exists and credentials are stored in `${HOME}/.iotlabrc`.
- After successful submission, a `tmux` session is run on the testbed, which connects to the `serial_aggregator` tool of the testbed.
- In order to configure node roles during runtime, the script interacts with nodes over built-in RIOT shell commands.
- The serial output is stored in a logfile which is located in your home directory on the respective testbed site.

## Examples
Run from [scripts](scripts) folder to:

- Deploy many-to-one in single-hop on iotlab-m3:
`./manage_exp.sh m3 single many`
- Deploy one-to-many in single-hop on iotlab-m3:
`./manage_exp.sh m3 single one`
- Deploy many-to-one in multi-hop on iotlab-m3:
`./manage_exp.sh m3 multi many`
- Deploy one-to-many in multi-hop on iotlab-m3:
`./manage_exp.sh m3 multi one`
- Deploy one-to-many in multi-hop on nrf52dk:
`./manage_exp.sh nrf52dk multi one`
- Deploy many-to-one in single-hop on iotlab-m3 and re-flash boards that are already deployed in an experiment with with ID `EXPID`:
`./manage_exp.sh iotlab-m3 multi one EXPID`