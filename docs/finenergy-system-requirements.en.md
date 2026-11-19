# FIN Energy System Requirements

Applies to the FIN Energy 0.16.0 candidate, November 20, 2026. [Chinese edition](finenergy-system-requirements.md). This document distinguishes the build baseline from acceptance on a customer's installation.

## FIN versions

| Environment | Delivery boundary |
| --- | --- |
| FIN Framework 5.3.0.2761 | Current SDK compilation and automated-test baseline. Actual activation through the native feature still requires a genuine HQ test license. |
| Earlier builds | Outside this package's dependency baseline and not offered as supported environments. |
| FIN 5.3.1 or other builds | Follow that release's migration requirements, build with the matching SDK where required and perform target acceptance. A higher version number is not proof of compatibility. |
| Desigo Optic 5.3 | Obtain the full build and OEM distribution details, check native `fin`, core and alarm modules and licensing, then validate on the target installation. |
| Linux or embedded devices | The source uses FIN's cross-platform runtime, but this candidate has not completed runtime acceptance on those targets. A matching FIN distribution, Java, native libraries, fonts, filesystem permissions and genuine license are required. |

See [build.fan](../finEnergy.pod/build.fan) for dependencies, including native FIN licensing APIs and the 5.3.0.2761 core/alarm baseline. Windows runtime records for the earlier energy application do not establish 0.16.0 runtime acceptance.

## Server and client

Use an operating system, processor, memory, storage and Java runtime supported by the selected FIN distribution. The customer Pod reuses FIN and does not require a separate Node.js service, SQLite database, time-series database or license issuer. Node.js/npm and the SDK are source-build dependencies only.


FIN's current general server reference is listed below. It is not a separately measured FIN Energy minimum.

| Item | FIN reference |
| --- | --- |
| CPU | Modern x86-64 processor at 2 GHz or faster |
| Memory | 4 GB, with 8–16 GB or more recommended |
| Storage | 32 GB SSD as a starting point, plus history and backup capacity |
| Network | Gigabit LAN |
| Java | Current general guidance is Java 21 or newer, preferably OpenJDK; also check the target distribution's compatibility requirements |

Source: [FIN system requirements](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/770708327/System%2BRequirements), checked November 20, 2026. Point count, history, applications, alarms and multiple projects affect capacity. This reference does not establish this candidate's compatibility with a Linux or OEM distribution.

No separate minimum CPU, memory or storage threshold has been measured for FIN Energy. Size the entire FIN instance for point count, history retention, query periods, cleaning rules and concurrency. Start with FIN's published system requirements and validate query and memory behavior using target project data. A demonstration project is not a capacity guarantee.

Use a maintained Edge or Chrome browser. The application provides Chinese, English and mobile layouts, follows the FIN user's language by default and retains manual switching. No exact minimum browser build is claimed. Manrope is packaged locally with system-font fallback for Chinese; no external font service is needed.

## Project and data

Both retrofit and new projects can use the application. Installation and activation require the appropriate FIN administration permissions and native energy feature. Every enrolled meter needs an explicitly bound primary energy point with native history enabled and matching energy type, unit and reading semantics. Missing usage remains missing. Submeter totals do not replace a virtual meter's own primary history.

Ordinary consumption does not require floor area. Area intensity requires a verifiable building, floor or service-area denominator. Building and floor areas can be edited in FIN Energy and stored in the original native `area` tag. Queries use current relationships and freeze the effective area source in the result.

Existing projects require explicit preview, backup and migration of application tags, callbacks and owned assets, with the old application's tasks stopped. Original record IDs and primary histories remain intact. See [Upgrade and rollback](finenergy-upgrade.en.md) and [native licensing](finenergy-licensing.md).

## Required before customer release

Obtain HQ's exact feature token and genuine test license. Record the target FIN build, OS and Java. Verify activation, restart, expiry, cleaned history reads, queries, alarms and recovery. Compatibility for the Belgian customer will be stated against that customer's accepted environment.

[FIN system requirements](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/770708327) · [FIN migration guide](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/33872281614/Migrations)
