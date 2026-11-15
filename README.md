# Console

A log viewer for Darling. It lists messages from the Apple System Log (ASL)
and syslog, including messages written with `os_log`, by polling `asl_search`
every two seconds and showing the standard ASL keys plus the `os_log`
subsystem and category.

It needs `syslogd` running (it serves the ASL store).

## Building

Console is built as part of Darling: this repository is a submodule at
`src/external/Console` and is installed as
`/Applications/Utilities/Console.app` in the Darling prefix.

## License

GPL-3.0-or-later, the same as Darling. See `LICENSE`.
