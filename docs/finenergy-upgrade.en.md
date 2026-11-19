# FIN Energy Upgrade and Rollback

This guide prepares an existing energy project for the FIN Energy 0.16.0 candidate. [简体中文](finenergy-upgrade.md). New projects do not need a legacy namespace migration. Verify this process in an isolated installation using a genuine HQ feature grant before customer delivery.

## Preparation

Record the full FIN build, OS, Java and candidate SHA256. The SDK baseline is FIN 5.3.0.2761. Obtain HQ's exact feature token and native test license before enabling the extension. A legacy RSA file cannot activate the native feature; the new UI and migration functions may be unavailable without it.

Use FIN's supported backup procedure to preserve Folio, the alarm store, original histories, private assets, the old Pod and extension configuration. Retain a recoverable complete instance backup. Migration-generated Zinc snapshots are not an instance backup. Save baseline report results with identical scope, interval, cutoff, energy category, primary points and cleaning rules.

Reserve a maintenance window. Stop the old application's rollups and alarm jobs, and pause configuration changes. Drain in-flight work first. Persistent maintenance ownership binds the original journal before publication and pauses queries, configuration, scans and rollups across interruption/restart until verified complete/rolledBack cleanup. Keep old tasks stopped throughout maintenance. Maintenance isolation applies to the affected project; unfenced projects continue housekeeping. Original FIN history is not relocated.

## Installation and preview

Stop FIN normally, verify process exit and port release, check the backup, remove the old application Pod from the loading directory, then install the single `finEnergy.pod`. Do not run both extensions as active business instances. Restart and check the genuine native feature state. Keep energy jobs paused and avoid normal application configuration before migration.

A project administrator runs a read-only preview in the target project's Axon tool:

```axon
finEnergyRenameNamespace("enerCubix", "finEnergy", false)
```

Inspect the project, namespaces, record/alarm/asset counts and revision. Target tags, singleton identities, continuity owners or duplicate jobs can stop migration. Resolve the actual configuration; do not delete records or force overwrites to bypass a conflict. Preview each project independently. Preview publishes no business changes.

## Explicit apply

After inspecting the preview, apply that reviewed revision in the maintenance window. This is the call form: replace `reviewedRevision` with the quoted `revision` string from the result you inspected. Do not automatically regenerate preview immediately before writing:

```axon
finEnergyRenameNamespace("enerCubix", "finEnergy", true, reviewedRevision)
```

The second example writes configuration and alarms and is for an administrator who has inspected the equivalent preview. Equipment and point IDs, standard FIN tags, primary histories and customer names remain. Product fields, structured references, owned cleaning callbacks, exact product scheduler expressions, recovery snapshots and private assets are migrated together. Custom task text is not globally replaced. Explicit exceptions for standard fields are owned `hisFunc`/`jobExpr` callbacks and the `dis` labels of product jobs/locks; these are updated by the defined mapping. Other native fields remain.

Retain the returned `backup`, `revision` and phase. Full snapshots and an integrity digest precede staged asset copying, Folio changes and native alarm updates. Phases include `prepared`, `filesCopied`, `recordsApplied` and `complete`. This is not a single cross-store database transaction. Routine current-value or acknowledgement changes do not invalidate the configuration fingerprint; relevant product changes require a new preview.

## Resume and recovery

If interrupted, retain the original backup identifier included in the error. Call `finEnergyResumeNamespace(backup)` with that actual returned string to continue the same journal. Integrity, resources and the complete projected graph are rechecked. Only valid before/after states are accepted. A new partial migration journal is not a substitute for completing the original operation.

To undo, call `finEnergyRollbackNamespace(backup)`. Recovery reverses only the fields changed by this migration and preserves current native values, acknowledgements and unrelated edits. Conflicting product changes or asset changes stop recovery. After rollback, reinstall the old Pod through the normal backed-up installation procedure and verify jobs and data. Do not swap the old Pod back before restoring its tags and callbacks.

A completed same-direction migration should preview no changes. Repeated resume or rollback still validates the original journal and current data. Idempotency does not remove conflict checks or the need for backups.

## Complete maintenance

Check IDs, relationships, primary points, history bounds, cleaning profiles, templates, budgets, assets and alarm acknowledgements. Compare consumption, end uses, costs and differences using the saved criteria. Check the new native menu and both languages. Update bookmarks to `/pod/finEnergy/res/web/finEnergy/index-0.16.0.html` and the API to `/api/{project}/ext/finEnergy/v1`.

After the original journal reaches `complete`, enable only one set of energy rollups and alarm jobs and verify their counts and scan scope. For recovery, confirm `rolledBack` before restoring the previous application. Finish these checks per project before leaving maintenance.

Browser migration retains only eligible per-user language and project display preferences. It does not impose a former global language setting on other users. Follow FIN and manual language switching remain available.

## Required release acceptance

Use real FIN licenses to test feature present, missing, expired, restarted and multi-project states, normal/raw history reads, cleaning callbacks and the native menu. Until then this is a candidate and test procedure, not a customer deployment claim. See [FinEnergyNamespace](../finEnergy.pod/fan/FinEnergyNamespace.fan) and [native licensing](finenergy-licensing.md).
