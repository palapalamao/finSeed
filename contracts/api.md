# EnerCubix application contract 0.12.0

FIN 5.3.0.2761. Same-origin authenticated JSON API at `/api/{project}/ext/enerCubix/v1`.
Success `{ok:true,data:...}`; failure `{ok:false,error:{code,msg}}` and non-2xx HTTP status. Never fall back to demo data. FIN native identity; admin-only mutations. Use `finCsrfFetch` from haystack-nclient for requests.

## Native equipment storage (0.4.0)

All normal meter/sensor saves, including batch assignment and role changes, write FIN's existing equipment record. Its ID is the physical equipment ID; `nativeEquip:true` and a model marker are not required to choose this storage path. Parent references point to upstream equipment IDs, and every equipment business scalar/reference is stored as a visible `enerCubix*` tag on that same record. Normal saves never create an independent meter archive. Editing retained historical archives first repairs their native equipment configuration with validated references, optimistic revisions and recovery snapshots; no user migration workflow is required. Shared tariffs, calendars, expressions and other project configuration retain their own records.

Meter `autoSum?:boolean` opts into a continuous cumulative reading on its existing `pointId`, advanced by direct-child increments after their individual baselines. Adding, removing or rebinding a source never imports its previous lifetime counter. Project `settings.meterRollupSeconds` controls the current-value update interval (integer 1–3600 seconds, default 1 when absent). A one-second FIN housekeeping callback checks the saved interval without restarting; runs remain serialized. Collected sources cannot be overwritten. Meter-owned minute consumption and quality are published separately as described below; report queries never rebuild a selected total from its current children. Native equipment configuration takes precedence over retained archives for the same point. The Other settings page preserves unrelated settings and the optimistic `mod` revision.

`catalog.storageModel` is `nativeEquip` for normal operation. Physical meter/sensor `id` and report `nodeIds` are FIN equipment IDs; `pointId` and report `sourceIds` remain native history point IDs. Three views use the same equipment record. `enerCubixAlias` preserves the short name without changing native `dis`/`navName`. References use the existing `enerCubix*Ref` tags on equipment; scalar properties use `EnerCubixNativeEquip.scalars` (`enerCubixArea`, `enerCubixMaximum`, `enerCubixHistoryMode`, `enerCubixIncludeInTotals`, etc.). The older archive description below documents retained compatibility data only.

Enrollment writes an existing equipment ID plus its observed `mod`, kind, category and explicit own historized compatible `pointId`. Batch saves are atomic and reject multiple records for one equipment. `tree/manage copy` requires `targetId`, `targetMod`, and the target equipment's `pointId`; it creates no physical archive. `records/delete` and `tree/manage delete` unenroll equipment by removing owned energy tags, preserving equipment, native hierarchy, points and histories. Native virtual equipment is created with `createVirtual:true`, `expressionId`, `siteId`, and a `floorId` belonging to that site; it is excluded from totals by default.

Ordinary meter creation uses `createNative:true`, `kind:'totalMeter'|'meter'`, `name`, `categoryId`, `siteId`, and a `floorId` belonging to that site. It requires no expression and binds no existing point. One atomic commit creates native equipment and its own Number point with matching site/floor references, the category unit (or a compatible selected unit), `his`, `hisTotalized`, site/project timezone and a 15-minute history collection interval. `enerCubixPointRef` targets that new point. Main meters default to `autoSum:true` and `includeInTotals:true`; no current reading or history samples are fabricated. The ordinary-meter entry and expression-device entry are separate; the latter visibly requires expression selection.

Native navigation supplies `nativeTreeParentId`; edits to existing equipment never write FIN location references. `spaceId` means coverage, inferred from installation location when absent. Invalid native tag types, point ownership, history, energy, references and topology appear as `configurationError` and produce `invalidConfiguration` quality instead of an energy value. Refresh reads native edits directly.

`migration/preview` now previews `target:nativeEquip`: old IDs, native IDs, primary points, upstream equipment, per-tag `tagChanges`, conflicts, configuration `revision`, and relevant-source `sourceRevision`. Apply checks both revisions and atomically writes owned tags, dependency rewrites, compatibility aliases, recovery snapshots, and the reading mode. Old physical archives are ignored after apply. `migration {action:finalize,jobId,mod}` removes those archives only after report verification; `rollback` restores old IDs/read mode and only migration-owned changes, stopping on conflicting later edits. Historical alarm source records remain immutable; old report IDs resolve via the compatibility aliases. Use `target:threeTree` only for the previous migration protocol.

## Configuration

`EnerCubixRecord` is an ordinary JSON object: `id?:string,mod?:string,kind:string,name:string` plus the fields below. IDs are FIN ref strings without `@`; stored relationship fields are native Folio Refs. Device properties use visible scalar/reference tags on the original equipment as described above. Shared project configuration uses its own Folio records and `enerCubixConfig` JSON, not files or browser storage. Kind is one of space,organization,group,meter,totalMeter,sensor,category,subcategory,utility,tariff,calendar,expression,cop,template,settings,binding,job,alarm.

- space/organization: parentId?,area?,description?. A space can have only a space parent; an organization can have only an organization parent. Their hierarchies are independent of legacy groups and meter topology.
- group: parentId?,area?,description?,alarmLimits:[{categoryId,limit,enabled}]
- meter/totalMeter/sensor: parentId?,spaceId?,meterParentId?,organizationId?,canonicalId?,pointId?,categoryId?,subcategoryId?,utilityId?,tariffId?,expressionId?,area?,maximum?,includeInTotals?,actualEfficiency?,baselineEfficiency?,alarmEnabled?,alarmLimit?,unit?,description?,location?. Meter/totalMeter `historyMode?:auto|cumulative|interval` explicitly interprets legacy histories inside EnerCubix without modifying FIN source tags or samples; explicit modes for the same point must agree. Unspecified mode preserves FIN configuration, including a standalone `hisTotalized` counter marker.
- category: unit; subcategory: categoryId,coalFactor,co2Factor,rawcoalFactor?,oilFactor?; utility: categoryId. Factors are output mass per category energy unit: coal in kgce, CO2 in kgCO2, raw coal/oil in kg. For example 0.1229 kgce/kWh yields 29.496 kgce for 240 kWh.
- tariff: categoryId?,isDefault?,mode=flat|absolute|weekly|monthlyBlock|yearlyBlock,rate:number,rules:[{from?,to?,startHour?,endHour?,weekday?,rate}],exceptions:[{from,to,startHour?,endHour?,rate}],blocks:[{limit:number|null,rate:number}]
- calendar: isDefault?,peakHours:number[],valleyHours:number[],workHours:number[],workDays:number[] (ISO 1 Monday..7 Sunday),exceptions:[{date:string,working:boolean}]
- expression: formula:string,variables:{[variableName]:meterRecordId}
- cop: numeratorId,denominatorId
- template: request:ReportRequest,preset?:thisWeek|lastWeek|thisMonth|lastMonth|thisYear|lastYear
- settings: visibleMetrics:string[],visibleCategoryIds?:string[],rotationSeconds:number. `visibleCategoryIds` selects the energy-category dashboard slides; omission selects all categories, while `[]` selects none. Cost/coal/CO2 slides are selected independently by `visibleMetrics`.
- binding: pointId,role=energy|reference|runtime,alias?
- job: action,enabled,status,from?,to?,message?,processed?,lastRun?
- alarm: nodeId,categoryId?,ts,value,limit,state=open|acknowledged,ackBy?,ackAt?,ackNote?

Meter relationships have distinct meanings: `spaceId` is coverage, `meterParentId` is the confirmed upstream meter, and `organizationId` is accounting ownership. Their native tags are `enerCubixSpaceRef`, `enerCubixMeterParentRef`, and `enerCubixOrganizationRef`. `canonicalId` / `enerCubixCanonicalRef` identifies an existing compatibility alias for the same point/expression and energy category; it references a canonical meter/sensor rather than another alias. Upstream meters must also be canonical and in the same energy category. Cycles and missing or incompatible targets are rejected. A physical point has one canonical meter record in the new dimensions; existing duplicate records can remain as legacy aliases. `parentId` / `enerCubixParentRef` on a meter continues to describe only its legacy group and does not imply any of the three new relationships.

GET `catalog` -> `{version,project,user:{name,canWrite},spaceSource:'fin',nativeTreePath,nativeTreeWarnings:string[],records:EnerCubixRecord[]}`. Each request reads the current native `legacy::NavTree.find(cx,"equip")`, preserving navigation names, ordering, nested equipment, point leaves and FIN access checks. There is no persistent mirror or synchronization write on a GET. Page refresh and workspace refresh fetch this projection again.

Native containers project as `kind:'space',nativeReadonly:true,nativeSourceId,nativeSourceKind,parentId`. IDs are native FIN Refs; an existing EnerCubix space with matching `migrationSourceId` keeps its ID. Point leaves use `kind:'nativePoint',nativeReadonly:true,nativeSourceId,parentId,nativeDis,unit?,his?,pointKind?`; these are browsing metadata, never energy archives or implicit history dependencies. The UI displays only point leaves with his:true, as confirmed by the user; all native containers remain. A bound eligible leaf displays its canonical archive under the original FIN leaf name. Historical manual spaces remain in the catalog with `nativeHidden:true` and are omitted from the current FIN tree.

Physical archives add transient `nativeSpaceReadonly:true,nativeSpaceId?` from the current point parent. Missing/inaccessible sources retain their archives with `nativeSourceMissing:true` and no live coverage; refresh never deletes archives or changes organization/upstream references. New/changed bindings persist the native parent as a Folio `enerCubixSpaceRef`; unrelated edits retain stored `spaceId` for historical requests. All `native*` fields are stripped before persistence. Native containers and leaves reject backend edits, moves, copies and deletion; maintain them in FIN. Unbound and virtual archives remain in the all-object list and other dimensions.
GET `tree?dimension=space|metering|organization|legacy` -> `{dimension,records:EnerCubixRecord[]}`. The default is `space`. The response is a flat directory: space/organization entities use same-kind `parentId`, and meters use the relationship appropriate to the requested dimension. New dimensions expose canonical meters; `legacy` includes original groups and compatibility aliases.
GET `points?q=&offset=0&limit=200` -> `{items:FinPoint[],total,offset,limit}` where FinPoint `{id,name,unit,kind,his:boolean,hisMode?,source?,hisStart?,hisEnd?,curStatus?,hisStatus?,hisErr?,hisLastCollect?,navName?,equipId?,equipName?,equipNavName?,floorId?,floorName?,siteId?,siteName?,energyTags?:string[]}`. Related labels and IDs come from readable native references; energyTags contains only native markers, never name-based guesses.
POST `records` body `{record:EnerCubixRecord}` -> saved EnerCubixRecord; update requires current mod.
POST `records/delete` body `{id,mod}` -> `{deleted:id}`. Reject referenced/occupied/cyclic/duplicate config.
POST `tree/copy` or `tree/move` body `{id,parentId,mod}` -> `{records:EnerCubixRecord[]}`.

POST `tree/manage` is admin-only. `action=save` accepts `{records:EnerCubixRecord[]}` (up to 200) and validates the entire final batch before a single Folio commit; new or changed physical bindings reject any existing meter binding to that point. Existing pre-migration duplicates can retain unchanged source references while their other fields are edited. Existing records require their current mods.
`action=move` accepts `{items:[{id,mod}],parentId}`; selected descendants remain under their selected ancestors. `action=totals` accepts `{items:[{id,mod}],included:boolean}` for meters only. Each change is atomic and validates cycles and master uniqueness against the final structure.

For new trees, use `tree/manage` with `dimension:'space'|'metering'|'organization'`:

- `action:'move',items:[{id,mod}],parentId:string|null`: moving a meter changes only `spaceId`, `meterParentId`, or `organizationId`; moving a space/organization changes its same-kind parent. A null parent clears that dimension's relationship. Other dimensions and legacy placement remain intact.
- `action:'assign',items:[{id,mod}],patch:{...}`: batch-update canonical meter records. Allowed patch keys are `spaceId,meterParentId,organizationId,utilityId,categoryId,includeInTotals`; null removes a field. The final candidate batch is validated before one commit.
- `action:'copy',items:[{id,mod}]`: copy one selected object as a new configuration record, clearing `pointId`, `expressionId`, and `canonicalId`, and setting `includeInTotals:false`. It does not copy descendants or duplicate the native source. Retained configuration relationships are subject to final validation.

Omitting `dimension` preserves legacy tree grouping. The original `tree/move` and `tree/toggle` routes retain their legacy relation semantics; use `tree/manage` for dimension-aware operations. Legacy `tree/copy` still copies the group hierarchy, but all copied meters clear physical/expression/canonical bindings and default to excluded-from-totals.
`action=previewDelete` accepts `{items:[{id,mod}]}` and returns `{revision,roots,records:[{id,kind,name}],blockers:[{id,kind,name,referencedIds}]}`. The complete EnerCubix subtree is selected; templates, expressions, COP or other outside configuration references block deletion. `action=delete` accepts the same items and preview revision; it rejects changed configuration and returns `{deleted:string[]}`. It deletes only EnerCubix configuration, retaining native points, equipment and histories. Alarm/job audit records follow the existing retained-event policy.

The engineering UI scopes direct children, descendants or all objects; paths follow the selected dimension's relationships, never name prefixes. Drag/drop and batch moves use the same validated backend. New physical meters default to included totals, sensors remain excluded, and reused meters retain their saved flags. The wizard suggests a category only when normalized unit and native-marker evidence agree uniquely; ambiguous batches require an explicit choice. Short aliases use explicit native naming metadata, with original names retained in provenance. Metering energy folders are presentation-only and cannot become report objects or relation targets. Desktop uses a right inspector and mobile uses a detail drawer. Advanced single-object fields are collapsed without discarding their saved values.

Native Axon administration: `enerCubixCatalog()`, `enerCubixNativeSpaceInfo()` (bounded read-only counts, path, signature and warnings), `enerCubixSaveConfig(json)` (admin only), `enerCubixManage(json)` (admin only), `enerCubixMigrate(json)` (admin only), and `enerCubixReport(json)` return `{result: JSON string}`. They use the same EnerCubixRepo validation, native FIN identity and permissions as the HTTP routes. Save accepts one EnerCubixRecord and preserves optimistic mod checks; bounded batches must reconcile partial results before retrying.

## Three-tree migration

All migration operations, including preview, require an administrator. GET `migration/preview` and POST `migration` with `{action:'preview'}` return the same plan:

`{version:1,revision:string,sourceRevision:string,records:EnerCubixRecord[],suggestions:MigrationSuggestion[],warnings:string[],counts:{added,updated,canonicalAliases,spaces,suggestions,unboundMeters}}`.

`records` contains automatic additions and full edited records. `MigrationSuggestion` is `{id,type,title,reason,requiresConfirmation:true,records:EnerCubixRecord[],patches:object[],recordIds:string[],sourceIds:string[],count:number,placementRequired?:boolean,parentId?:string}`. Suggestion types include `legacySpace,nativeFloor,meterTopology,legacyGroup`. Full proposed records support review; field patches allow independent space and topology proposals to be combined without resetting each other's changes. A `placementRequired` suggestion contains no automatic placement and needs an explicitly selected target space.

POST `migration` with `{action:'apply',revision,sourceRevision,acceptedSuggestionIds?:string[],placements?:{[suggestionId]:spaceId}}` applies the automatic records plus accepted proposals and explicit placements. Both revision values must be copied unchanged from the preview. The server regenerates the plan and compares the EnerCubix configuration revision and native-source metadata signature; changes require a fresh preview and return HTTP 409 / `CONFLICT`. Unknown proposal IDs or invalid placement targets are rejected. A placement key must identify a `placementRequired` suggestion; its target must be an existing space or a new space included by an accepted proposal. Overlapping explicit placements must agree for each meter. The complete candidate is validated before one Folio commit. The response is `{applied:number,job:EnerCubixRecord|null}`; a no-op returns zero and no job.

Migration creates only assured site roots and source-backed placements automatically. Native `submeterOf` is carried over only when all supplied references map unambiguously to the same existing canonical upstream meter in the same energy category and do not introduce a cycle. Native floor names may be functional groups, so floor/building placement inferred from names remains a confirmation proposal. Functional groups such as 总能耗 and 风机盘管 require an explicit target; groups with no meters remain unbound. The 1#楼水表 wrapper pattern can produce a batch topology proposal whose parent is the canonical record for the existing master point; sharing a group or a name never creates automatic topology.

Duplicate point aliases receive `canonicalId`; canonical selection prefers an included active total meter, otherwise a deterministic existing record, while retaining a consistent prior canonical choice. Incompatible categories/expressions produce warnings. Generated space IDs are deterministic qualified FIN refs, so re-preview after application does not create duplicate additions. Existing groups, meter `parentId`, original point bindings, and legacy total flags remain intact. Migration never writes native FIN point/equipment tags or source histories.

Applied migrations retain a `job` with `action:'treeMigration',status:'applied',migrationKey,processed`, plus retained `treeMigrationSnapshot` job records containing before/after EnerCubix configuration. POST `migration` with `{action:'rollback',jobId,mod}` requires the current migration-job mod and returns `{rolledBack:number,job:EnerCubixRecord}`. Rollback compares current business fields with the saved after-state, rejecting changed or missing migrated records with HTTP 409. It also validates the restored candidate and rejects deletion of migration-created objects that acquired external references. A successful rollback atomically restores prior records, removes migration-only additions, and marks the job `rolledBack`; audit/snapshot records remain retained. This is a EnerCubix configuration rollback, not a native-history backup.

## Reports

POST `report` body ReportRequest -> ReportResult.
ReportRequest `{kind,nodeIds:string[],dimension?:'space'|'metering'|'organization'|'legacy',from:string,to:string,period:'hour'|'day'|'week'|'month'|'year',metric:'energy'|'cost'|'coal'|'co2'|'rawcoal'|'oil',perArea:boolean,referenceIds?:string[],otherFrom?:string,otherTo?:string,xId?:string,yId?:string,workHours?:number[]}`. Dates are ISO 8601 with timezone, intervals [from,to), buckets in project timezone. kind=profile|ranking|proportion|utility|daily|comparison|primary|cop|leak|workingHours|workingDays|regression|trend|dashboard. Empty selections do not imply all records except dashboard. Normal values match legacy business meaning, anomalies stay null + quality.
ReportResult `{kind,from,to,period,series:Series[],rows:object[],warnings:string[],summary:object,extra:object}`.
For `ranking`, the server narrows the requested interval to the intersection of the selected sources' available history boundaries. Counters require two usable readings; interval histories require complete normalized hours. It never expands outside the request, drops a selected source, or removes internal gaps/resets. When narrowed, `from`/`to` are the actual statistics bounds and `rangeAdjustment:{status:'adjusted',requestedFrom,requestedTo}` preserves the original selection. If no common interval is available, bounds remain unchanged and `rangeAdjustment.status` is `'unavailable'`; ordinary missing/abnormal quality is retained. Other report kinds retain their existing interval behavior.
Series `{id,nodeId?,name,categoryId?,unit,points:[{ts:string,value:number|null,quality:string,sourceIds:string[],band?:string,x?:number,label?:string}]}`. Ordinary table rows include `{key,nodeId,name,categoryId,unit,value,quality,sourceIds}` plus report-specific fields. `summary.totals`, when present, contains `{id,name,categoryId,value,quality,unit,sourceIds}` for non-reference series. All aggregates are calculated by the engine, not the client.

Omitted `dimension` or `dimension:'legacy'` uses the original analysis path exactly: legacy groups, `parentId`, total-meter selection, flags, and historical template requests keep their previous meaning. Migration does not reinterpret old report requests.

New space reports and templates carry `spaceSource:'fin'`. Only `dimension:'space',spaceSource:'fin'` resolves current FIN membership via `nativeSpaceId`; old requests/templates without this flag use raw persisted records and previous `spaceId`/hierarchy. Native leaves must be bound to archives before energy analysis. Source omissions produce warnings instead of reusing historical coverage.

For new dimensions, compatibility aliases resolve to canonical records before membership and dependencies are evaluated. `space` includes meters placed in the selected space or descendants according to the above source flag; `organization` uses the ownership subtree. Totals include eligible canonical physical meters and suppress a descendant when its confirmed upstream meter is already included in the same scope. A floor scope can therefore read its own meter even when a building scope uses the building master. `metering` follows confirmed `meterParentId`; selecting an individual meter reads its own history, and leak analysis subtracts only confirmed direct children.

Unresolved overlapping master coverage or invalid/missing upstream topology yields `value:null,quality:'topologyIncomplete'`. Ownership that cannot be separated from another owner's measured branch yields `accountingIncomplete`, also with a null aggregate. Missing histories retain their existing quality and source evidence. These cases do not become zero or an invented allocation. Ordinary aggregated dimension reports add `extra.details:[{scopeId,nodeId,name,categoryId,value,quality,unit,sourceIds,counted:boolean}]`, preserving the individual readings even when the aggregate is withheld; `counted` identifies the selected topology frontier. Raw trend and regression retain their report-specific output.

New-dimension utility analysis accepts only root and first-level space/organization scopes; deeper scopes and the metering tree are rejected. It groups confirmed measured end branches by `utilityId`, including an unassigned-use bucket; an unexplained master-minus-branches difference is not assigned a use. Leak calculations require a meter selection and complete usable topology; missing branches remain null with quality evidence.

Report-specific fields:

- leak: each period row retains `total`, `submeter`, `difference` (= total minus submeter) and `percentage` (= difference / total × 100). Additive `extra.leakBranches:[{nodeId,branchId,name,categoryId,unit,ts,value,quality,sourceIds}]` contains each eligible direct branch in the same period and unit; per-area values use the selected master's area for both bars. `extra.leakTotals` contains the corresponding interval aggregates with ordinary row identity/quality/source fields. The chart shows the master beside a stack of individual branches; the difference is separate and negative values remain visible with a warning. If a branch is missing, the complete submeter aggregate remains null and the chart leaves the whole stack blank. Existing difference series remain compatible. Weekly buckets begin Monday in the project timezone; partial first/last buckets include only data inside `[from,to)`.

- dashboard: `extra.overview:[{key,value,quality,sourceIds}]`, with `key=categoryId|unit`; `extra.grandTotals:[{key,name,unit,value,quality,sourceIds}]`, with `key=metric|unit`. Grand totals combine only matching units, so incompatible energy units remain separate. Optional comparison ranges also produce `extra.comparisons`.
- utility: `extra.utilityShares:[{id,name,nodeId,categoryId,unit,value,percentage,quality,sourceIds}]`. Explicitly selected metering objects remain independently analyzable even when `includeInTotals:false`; that flag still controls their admission into automatic parent aggregates. Metering views accept canonical meters and master meters at any depth, following confirmed upstream links and grouping the non-overlapping end branches by utility. Spatial and organization views retain their root/first-level scope limit; `extra.scopeTotals` retains the selected scope total for coverage checks. Each percentage uses the utilities within the same node/category/unit as its denominator; this differs from the proportion report's selected-object percentages.
- daily: points add `band:'peak'|'valley'|'flat'|'unknown'`; rows add `hour:number,ts:string,samples:number,band:string`. Energy points show the mean for each hour of day across the requested interval, described by `extra.aggregation='mean energy for each hour of day'`. `extra.loadBands` contains ordinary rows plus `band`, with interval energy totals by band, and `extra.loadBandsAggregation='intervalTotal'`; these are not sums of the daily-average points. Missing calendars use `unknown` and a warning. Nonempty gauge/ratio bands return null with `invalidMetric`.
- regression: points add `x`, rows include `{key,ts,x,y,value,quality,sourceIds}` where `value=y`. `extra` contains `{slope:number|null,intercept:number|null,r2:number|null,count:number,equation?:string,xName:string,yName:string,fitLine:[{x:number,y:number}]}`. `fitLine` contains the fitted endpoints at minimum/maximum X, or is empty when a fit cannot be calculated. Incomplete pairs are omitted with warnings; fewer than two valid pairs or constant X leaves fit coefficients null.
- comparison: `extra.comparisons:[{id,name,current,reference,difference,percentage,quality,unit,referenceName?}]`; explicit comparison ranges also append reference series whose IDs end in `|reference`.
- trend: `extra.aggregation='raw samples'`; reads the selected object's own FIN point with `{raw}`. Points retain every original timestamp, value and null/NA type inside `[from,to)` without cleaning, report-period bucketing or expansion into child histories.

## Engine boundary (Fantom, owned by calculation worker)

`EnerCubixEngine.report([Str:Obj?] request, [Str:Obj?][] records, [Str:Obj?][] histories) -> [Str:Obj?]` returns ReportResult. Each history `{pointId,unit,mode:'cumulative'|'interval'|'sampled'|'cov',samples:[{ts:ISO8601,value:Float?}],quality?:string}`. Histories include needed leading/trailing values. Point ranges and sampled missing data must not silently become zero. Engine is pure, never modifies source histories. It interprets records/refs only from supplied data.

## Tasks and alerts

FIN's extension housekeeping checks the configured update interval every second. Only canonical native `meter`/`totalMeter` equipment explicitly configured with `autoSum:true` (`enerCubixAutoSum:true` on the equipment) advances its own `enerCubixPointRef` from direct-child increments. The flag defaults off; `enerCubixKind:totalMeter` and a parent relationship alone never authorize overwriting a measured point. A point carrying any `*ConnRef` collection tag is always protected, including when the flag was manually enabled; normal configuration rejects this combination. A measured intermediate meter contributes its own reading rather than the sum of its descendants. Calculated levels are evaluated bottom-up; compatible units are converted and sensors/aliases excluded. Report-only `includeInTotals` does not change generation membership. Source baselines and cumulative continuity are persistent; `enerCubixRollupRef/At/Status` expose current calculation state, and `enerCubixRollupHasGap` retains evidence of omitted or uncertain increments. Missing inputs, resets, incompatible categories/units and cycles fault only affected targets. Separate closed-minute publication saves consumption and quality without device commands or changes to source raw history.

POST `tasks` body `{action:'recalculate'|'setCalculationEnabled'|'setAlarmEnabled'|'scanAlarms',from?,to?,enabled?}` -> job EnerCubixRecord; task status is persisted in Folio. Recalculation corrects published owned-minute intervals and their dedicated mirrors using effective historical configuration; source raw samples remain untouched. Native source-history sync and derived recomputation remain distinct.
GET `alarms` -> EnerCubixRecord[] alarm records. POST `alarms/ack` `{id,mod,note}` -> acknowledged EnerCubixRecord, actor from FIN session only.

## Presentation

Desktop sidebar + selectable analysis tree + filters + report workspace, collapsed navigation on mobile. No custom login, user admin, theme picker or hardcoded sample data. All existing business configuration kinds have usable forms; complex tariff/calendar rules get structured editors. Keep FIN project in hash query `#/profile?project=...` because pod resource serving rejects search query on some FIN builds.

### 对比区间对齐（0.2.9）

`comparison` 可选 `comparisonAlignment: "duration" | "calendarMonth"`。`duration` 要求两期时长严格相等，仅支持 hour/day/week，并从各自区间起点生成等长汇总桶；`calendarMonth` 要求两期均为完整自然月且 period=month，保留月份实际天数。未传参数的旧请求继续使用原自然时间桶与区间。`comparisonPreset` 由前端模板解析，后端以已解析的 from/to/otherFrom/otherTo 为准；日期控件包含结束日，传输仍使用左闭右开区间。图表按桶序配对，不移动或改写原时间戳。

### 对象对比基准（0.2.10）

同一时段的 comparison 请求可指定 `baselineId`，它必须属于 `nodeIds`；三维请求按同样规则规范化该引用。后端按对象及能源分类、单位匹配基准，返回 comparisonBaselineId/Name，以及 comparisons 中的 referenceId/Name、current/reference、difference、percentage 和 percentageQuality。缺失或不兼容时保留系列并提示，差值及变化率为空；零基准变化率为空。未提供 baselineId 的旧请求继续按首对象比较。模板将该引用保存为 Folio 依赖 Ref。新页面统一使用 nodeIds 选择对象，旧模板可继续带 referenceIds。

### 能耗预测（0.3.0）

`kind: "forecast"` 使用 `metric: "energy"`、`period: "day"`，`from/to` 为项目时区中 28–180 个完整日的训练区间（结束不含），截止不得晚于今天零点。选择 1–10 个表计或统计范围，`forecastDays` 取 7（默认）、14、30。`trainingDays`、`forecastRolling` 保存前端模板意图，服务端以解析后的日期为准。源历史只读，计算前剔除训练截止后的样本；累计读数在截止时的精确边界可以使用。

至少需要 28 个有效日、80% 完整率、每星期位置三个有效日及最近七天完整数据。按预测长度最多留出四个不重叠的滚动回测区间，每次仅用此前历史训练；比较上周同期、近期同星期加权均值、周周期加权衰减趋势，以 MAE 选择，复杂模型须改善超过 2%。30 天预测需要至少 44 个日历日才能形成一次回测。WAPE 在实际用量合计为零时返回空值。模型选择与评估共用这些历史留出区间，回测误差不是独立测试集或未来准确率保证。

系列增加 `role: "history" | "forecast"`；预测点质量为 `predicted`，包含 `lower/upper`；明细增加 `phase/model`。`extra.forecasts` 返回各对象预测合计、模型、MAE、WAPE、基准 MAE、样本覆盖、状态及模拟来源标记；`extra.backtests/modelScores` 保留回测证据。每日参考范围采用所选模型回测绝对误差第 90 百分位，不保证未来覆盖率。数据不足时保留历史、无预测系列并给出原因。模型不使用天气或运行计划，各对象独立预测，不能重复合计总分表。图表、表格及导出使用同一结果。旧 `regression` 接口、链接和模板仍保留兼容。


### 数据清洗（0.10.0）

`records` / `records/delete` 支持 `kind:"cleaningProfile"`。字段为 `name`、`mode:"drop"|"replace"|"rollover"`、`parameters`、`version`，修改同时提交原 `mod/version`。通用初始参数为 `{deltaMin:0,timeMax:"1h",defNull:true}`，没有默认最大增量。清空可选参数即删除规则。`defNull/removeNA:true` 写入原生 Marker，关闭时移除标签。普通数值按源点单位解释；带单位数值为 `{type:"number",value:0,unit:"kWh"}`。`defVal` 必须用此显式数值类型或 `{type:"na"}`，后者表示真实 Haystack NA。回卷周期为数值（0..32767 的计数器填 32768），并必须设置有效的正增量或变化率上限。

设备配置增加 `cleaningEnabled/cleaningProfileId`，分别持久化为设备上的 `enerCubixCleaningEnabled` Marker 和 `enerCubixCleaningProfileRef`。主点使用 `hisFunc:"enerCubixCleanHis"`、原生 Dict `hisFuncConfig`、`hisFuncWritable` Marker，以及 `enerCubixCleaningOwned/ProfileRef/ProfileVersion/EquipRef/Original/Applied/Rollover` 标签。现有手工历史函数返回 `cleaningStatus:"externalFunctionManaged"`，不会被接管。取消纳入或关闭清洗只恢复本模块拥有的设置。方案修改和引用点更新为同一次 Folio 乐观并发提交。

内置函数 `enerCubixCleanHis(rec,dates,opts,yield,config:{})` 和报告共用对象自身历史的读取核心。正常用量按 `[from,to)` 输出区间开始时间戳；内部差分证据保留结束读数时间，仅转换一次。手工 `hfTotalized` 在 `hisMode:"consumption"` 下的开始戳不会再次前移。显式 `{raw}` 始终读取原始历史。启用独立用量归档后，普通查询优先读取该点已发布的用量和质量，保留其生成时的配置版本；尚未发布为归档区间的自身原始读数（包括切换前历史），新查询应用当前已保存且通过校验的清洗方案，显式参数覆盖优先。关闭清洗后不再应用旧方案，外部历史函数保留自身输出约定。跨切换查询组合按当前规则读取的原始历史前缀和已发布用量后缀，不改写任一来源。旧报告快照及其导出保持冻结；调整已发布历史仍须单独指定时间范围修正。显式预览使用所选候选配置且不写入历史。普通查询不按当前子表或当前公式重新汇总旧结果。未知外部函数必须明确声明输出为累计或区间类型。

POST `cleaning/preview` 接收 `{nodeId,from,to}`，也可明确传 `pointId/profileId/profile`；只读用户可使用。范围大于零且最多31天，返回 `raw/cleaned/details/summary/profileSnapshot`，不改写历史。`valueType:"number"|"null"|"na"` 区分零、缺值与 NA。调试明细记录原始值、前值、时长、触发原因及替代标记。

报告 `extra.cleaning` 保存方案ID、版本、完整参数、来源及过滤/替代/NA计数和覆盖率。`filtered` 用量表示有效小计，`substituted` 表示含替代值；NA 传播为 `value:null,valueType:"na",quality:"na"`。不完整小计可用于明确标注的已有用量平均、最高及已有用量占比；完整范围指标、COP、差额和阶梯费率继续执行完整性校验，重算不会写成完整实测值。报告中的异常明细最多1000条，并返回 `detailsTruncated`；预览保留所读范围的调试明细。已有导出快照保留生成时参数与结果。

### 能流图（0.8.0）

report 新增 kind: "energyFlow"；固定 dimension: "metering"、metric: "energy"、perArea: false，categoryId 必须为一个有单位的能源分类。nodeIds 为空时查看项目概览；一个对象查看该计量子树，多个对象按去重后的计量入口展示，并规范化兼容别名。请求仍使用项目时区的 [from,to)；整段用量通过原有历史解释和单位换算逐小时汇总，不是实时功率。

extra.energyFlow 返回 categoryId、unit、focusId、rootIds、nodes、links、unassigned。节点包含 id、name、nodeType（meter / summary / difference）、parentId（可选）、categoryId、unit、value、quality、sourceIds、submeter、difference、balanceQuality、hasChildren、percentage。连线包含 source、target、value、quality、sourceIds、percentage。rows 与 series 同时保留各节点读数、质量及来源，供明细与导出使用。

项目入口仅包括同能源、计入合计、没有计量上级且明确标为总表的主档案；兼容别名去重，下级不重复计入项目总量。未归属或无效计量链单列 unassigned，覆盖关系无法确认时项目汇总为 null / topologyIncomplete，不自动把孤立分表视为新入口。父级明确排除的计量子树不会被提升为独立入口。源点和历史只读。

每个非叶节点仅减去直属分表。正差额增加合成差额节点；零值不绘制比例流线，叶节点不产生差额。缺测、单位不兼容、无效计量关系及负差额保留读数和质量信息，停止绘制受影响分叉的连线；负差额保存在父节点 difference 中，balanceQuality 为 negativeBalance，不构造负宽度或补偿能源入口。比例只在有效且大于零的父子读数之间计算。

前端单次获取完整子树，默认展示三列并在查询快照内下钻。导出冻结当前可见范围，父级路径上下文不混入所选子树的统计明细；模板保存能源、时间和当前子树，保留相对时间查询规则。0.11.0 起，历史能流按已记录的关系生效区间分段；未记录的旧关系明确显示未知，不能套用当前关系。

### 对象自身历史与生效关系（0.11.0）

0.11.1 修正正式报告入口：`leak/energyFlow` 的历史关系分段由服务端从生效快照注入，不接受客户端伪造该内部证据。能流图进一步按各表自身历史的共同区间边界区分完整时段、缺测或异常时段与尚未发布的末段；不同采集间隔不要求时间戳逐条相等，不分摊不完整区间，也不将缺口变为零。历史快照中同一源点的原生表计与旧档案按当时保存的绑定消除重复，不使用今天的关系推定过去。

0.11.2 默认展示全查询区间总览，原始 `from/to` 保留；不再默认将最长完整子时段当作整周结果。`extra.energyFlowOverview:{from,to,unknownTopologySeconds,rows}` 与顶层 `rows` 独立列出各表自身历史，绝不合计总表和分表。每行提供 `value/quality/valueType/complete/coverage/activeSeconds/coveredSeconds/removed/sourceIds/periods`；覆盖率按时长计算，只累计完整落在查询及生效范围内的自身用量区间，累计读数的跨界区间不插值补算。`periods` 保留合并后的质量时段、缺口和源点，零、NA、过滤与替代分别保留。增删、迁移和换绑使用各自生效配置；历史成员仍列出其有效期数据，换绑不混用当前点，分类单位变化先换算为统一单位。旧关系未知时依然读取各表自身历史，但不生成流线、差额或泄漏结论。切换关系时段后，图、表及导出只使用该段快照，并移除全区间总览及不适用于该段的清洗摘要。

生成端在已结束的整分钟区间上处理自身采集、直属子表或公式输入，保留一分钟采集等待；每次每个对象最多追赶四分钟。输入按时间覆盖对齐，允许的一小时以内边界分摊标记为 `estimated`；缺测、NA、重置、过滤及替代值保留各自质量，不能变为零或完整实测。虚拟子表使用自己的已归档区间，不重复展开孙表。配置变更记录生效快照，启用前的计量关系不作推断。

对象的权威用量区间与质量、来源及配置版本在同一次 Folio 发布中保存，专用原生用量历史点作为镜像。生成游标持久化，原始采集历史不被改写。历史修正通过 `tasks` 的 `recalculate` 明确指定整分钟范围；拒绝未来、未生成及关系未知的区间。修正保留前后版本、按依赖顺序更新汇总结果，不倒退实时游标，也不把修正量再次加入实时累计读数。

泄漏与能流分析分别读取总表及涉及分表各自保存的历史。独立实测上游使用 `balanceMode:'independent'`；由同组分表生成的虚拟上游使用 `balanceMode:'consistency'`，差额为一致性检查。未知来源或关系使用 `balanceMode:'unknown'`。`lossEligible` 明确是否可作损耗判断，缺测、关系不明及负差额不会给出有效泄漏结论。负差额原值保留。`extra.energyFlowSegments:[{from,to,known,energyFlow,rows,series,summary,warnings}]` 返回历史关系分段；界面选择某段后，图、表及导出均使用该段快照。

### FIN 原生报警（0.8.3）

小时能耗超限保留逐小时能源证据；同一对象、能源分类和单位的持续超限共用一条原生 Alarm。`episodeId` 对应 Folio 的 `enerCubixAlarmEpisodeRef`，指向本次持续超限的主事件；`nativeAlarmId` 对应 `enerCubixNativeAlarmRef`。原生状态为 `offNormal`，优先级遵循 FIN 原生设置，要求确认。有效正常小时（quality 为 ok / derived 且 value <= limit）结束当前事件，恢复时间为该小时结束时刻；缺测和不确定数据不会推断恢复，恢复后再次超限产生新事件。物理点已有的连接器报警保持独立。

GET `alarms` 每次持续超限返回一行，包括 episodeStartTs、lastTs、recoveredAt?、hourCount、latestValue、peakValue 及 hours[]（ts、value、limit、unit、quality、原确认信息）。确认人、确认时间和备注以原生 Alarm 为准；原生正常且已确认后归档时保留确认快照。POST `alarms/ack` 使用原生确认接口，保留管理员权限及本地 mod 检查，旧小时事件 ID 也解析到主事件。确认与恢复正常互相独立；恢复但未确认的原生报警仍可确认。`nativeState`、`nativeActive` 返回原生状态；正常归档返回 nativeActive:false，其他被移除的原生记录返回 `nativeAlarmMissing:true`，均不会重新创建。

首次扫描回放旧小时事件至所选结束时间以识别恢复边界，后续从活动事件上次已评估小时续查，最长 366 天。合并前把本功能拥有的重复原生当前记录完整保存至原小时事件 nativeAlarmArchive，并保留 priorAckBy / priorAckAt / priorAckNote；然后仅移除这些重复当前记录，原生历史不清除。已确认的旧事件不会重新打开。重复扫描可找回创建成功但未保存关联的原生记录，且不重复生成小时证据或事件。任务 alarmsCreated 统计新增小时证据数。管理员 Axon `enerCubixScanAlarms(from,to)` 与页面扫描采用同一有界任务及共享锁。原生 metadata 包含 `enerCubixEnergyAlarm`、`enerCubixEventRef`、`enerCubixNodeRef`、`enerCubixCategoryRef`、`enerCubixSourceRefs`、带单位的 `sourceValue` 与 `enerCubixLimit`。

### 跨模块基础用量与数据截止（0.11.5）

报告保留调用方的 `[from,to)`，排名不再缩短请求时间。可传 `asOf` ISO 日期时间；FIN 服务将未来截止时间限制为服务器当前时间，响应返回实际 `asOf`。同一查询范围切换模块、视角或汇总间隔时界面沿用上次截止时间；同条件再次查询更新截止时间。模板保存选择范围及维度，不固定旧报告的数据截止。

非费用的概况、排名、占比、分项、对比、日均、工作时段、工作日、折算与概览共用 `closedSourceIntervals` 已有用量。仅纳入完整落在查询范围且在截止前闭合的源区间，不按时间比例补算。有限的过滤后小计可见，真实零保留；缺测、NA 不补零。`knownValue/knownValueType/knownQuality` 与严格的 `value/valueType/quality` 分开返回；客户端只在冻结的展示副本中采用已有用量，并保留 `complete*` 字段。图、表和导出使用同一副本。

`summary.selectionTotals` 及 `extra.selectionTotals` 按有效表计集合去重，含 `meterIds/sourceIds/knownValue`。相同有效表计集合、单位、清洗规则和截止应有相同基础合计。父子同时选择只计有效上级一次；重叠空间／组织范围不重复累加。组织未分配不抹掉设备自身已知用量，但结算归属及完整性单独标记。`usageCoverage` 记录实际覆盖与查询时长；`knownUsage.sourceUsage` 的诊断区间总计最多1000条，截断标记不改变数值及覆盖统计。

排名保留无数据对象，`rank:null`；占比以明确标注的已有用量为分母，单个正值为100%。零合计、负用量、范围重叠或无有效量分别返回 `percentageBasis` 原因并不生成饼图比例。对比保留 `knownCurrent/knownReference`，仅完整可比覆盖生成差值及变化率。费用、COP、泄漏／计量差额、预测训练及虚拟值发布不因已有用量展示而放宽条件。

能流支持 `scopeDimension/scopeNodeIds` 将空间／组织选择解析为同一有效表计集合。全区间总览按每块表自身有效主点历史计量，关系编辑的切片边界不截掉原始用量；历史换绑仅按各有效主点窗口读取，不按比例拆源区间。分段能流及平衡仍按当时关系核算，分段结果不保证可直接相加得到全区间自身用量。

### 配置有效版本的项目 ID（0.11.6）

新建配置的有效版本在提交前使用 Folio 的项目 ID 前缀规范化本地 Ref，保持配置 `id`、设备业务引用、分类和表达式变量与提交后的原生记录一致。项目限定的绝对引用保留原值，跨项目及失效引用仍由现有校验处理。

读取既有局部 ID 版本时，在内存中规范化已定义的引用字段；历史表达式虚拟设备由旧局部设备 ID 派生的历史点键，仅在匹配确定性旧键时兼容定位到原生设备的派生点。版本生效时间、参数和先后顺序保持原有语义，不改写已存 epoch JSON、原始读数或既有发布区间，不需要手工编辑配置或迁移；既有发布区间的修正仍通过明确范围重算执行。

虚拟表用量生成的状态键与引用使用提交后的完整主点 Ref；新增派生点时仍按 Folio 规则传入局部新增 ID，避免状态查找与原生点记录落在不同命名空间。

### 虚拟表归档点引用（0.11.7）

原生虚拟设备目录中的 `historyPointId` 与实际归档点使用同一项目限定 Ref；独立无项目前缀的记录保持原有引用格式，派生点的确定性名称保持不变。普通报表仍只读取匹配的已发布历史，不重新计算表达式，也不根据局部后缀匹配其他项目的点。

`includeInTotals: false` 继续排除范围合计；显式选择该虚拟设备时，趋势、排名、占比和对比仍可读取自身已归档用量。缺失归档继续返回缺测，不回退为实时表达式值。

### 当前关系计算（0.12.0）

用户于2026-10-26明确选择：所有报告及虚拟表后续生成、显式重算均使用当前关系和当前来源绑定。关系变更的历史仅作审计日志，不参与计算。本条替代上文历史关系回放、未知关系门槛及恢复关系参与报告的旧版本约定。

### 局部对照选择（0.12.0）

新泄漏报告传 `comparisonBasis:"physicalBoundary"`，并选择原生主表 ID；仅用于 `kind:"leak"`。不传此字段的旧模板保留原自动合计成员规则。三种视角均使用当前配置，`includeInTotals` 只控制自动汇总，不限制明确的自身用量查询或新局部对照。

只读 `GET comparison-scopes?nodeIds=<逗号分隔且URL编码的主表ID>` 返回 `{scopes:[{nodeId,categoryId,basis,availableMembers:[{nodeId,name,unit,via,sourceIds}],defaultMemberIds,selectedMemberIds,quality,completeSelection,limitations}]}`。`via` 是可读中间计算节点 ID；来源是本次配置绑定的实际历史点。最多200个主表，普通已登录只读用户可查询。服务端报告重新解析成员及权限，预览不是授权凭据。

`comparisonMembers?:Record<string,string[]>` 按主表指定：缺少该主表键表示全部当前可用边界，`[]` 明确不选任何分表，非空名单只能是该主表边界的子集；错误主表键、外部分表及无效类型返回400。兼容映射先规范化主表及分表 ID，同源别名只读一次。临时名单不写回资产。

解析穿透同能源、兼容单位的加法计算节点，遇到独立物理表停止，不同时累加它与下级。带权、减法及其他非加法节点保留其自有历史并返回范围限制，不临时展开重算。虚拟总表始终使用自身归档，缺失时为空，不以分表和补造。成员不完整、循环、缺少来源、单位不兼容或不可读时保留可读成员已有量，严格差额及比例为空，`lossEligible:false`；不返回隐藏成员的名称、ID和源点。

完整的独立实测总表在物理用量指标下才可获得泄漏资格；计算总表是计算汇总校核。费用及折算可显示差额校核，不输出物理漏损比例。单个分表缺测不清空其他分表堆积段。

响应 `extra.comparisonScopes` 固定实际成员、绑定和限制，`extra.comparisonUnion` 按能源及单位展示各主表所选分表的来源并集，去掉同源别名和物理父子重复；各主表组分别保留，不能直接把组和相加。不能安全相加的未解析边界合计为空；跨范围面积分母不明确时归一化并集合计为空。图、明细和导出使用同一冻结结果，模板保存依据及明确名单；分类筛选保留上述范围证据。

- 每次查询固定当前配置，并读取原请求日期内各表自身的历史；不按日志开始时间、旧父引用或旧点绑定切分查询。当前关系修改后的新查询会重新归组，已生成报告和导出保持原快照。
- 服务端与纯引擎入口忽略外部 `meterHistorySegments`、`legacyMembership`、`leakSegment`。日志缺失、晚于查询日期或包含旧关系均不改变成员、数值、覆盖或漏损资格。
- 结果 `extra.relationBasis` 固定为 `current`。能流仍可依据源数据覆盖划分展示区间；这些区间全部使用当前关系，与关系变更日志无关。
- 分表堆积显示当前成员的已有量。一个分表缺测不补零，也不清空其他分表已有段；严格差额和漏损资格继续受数据完整性、独立来源、单位及权限约束。
- 虚拟总表的后台计算、表计自有历史和原始读数保护保留。普通查询不会重新计算或改写已发布结果；后续生成和显式重算不读取历史关系配置，发布证据中的配置指纹来自当前计算配置。
- 自动汇总的 `includeInTotals` 及去重规则保持原语义。关系日志不提供另一套计算模式，也不要求普通用户确认或导入恢复凭据。

### 消息中心重要变更（开发分支，未部署）

GET `messages/changes?offset=0&limit=30` 返回 `{items:ChangeMessage[],total,offset,limit}`。`offset` 为非负整数，`limit` 为 1–200，默认30；非法范围返回400。沿用现有 `{ok:true,data:...}` 响应包装。只读接口不确认、不重算、不改写配置或日志；现有 `alarms` 与 `alarms/ack` 保持原行为。

`ChangeMessage` 为 `{id,ts,action,category,objectId,objectName,objectKind,actor?,changes:[{field,before,after}],detailsRestricted?}`。`action` 为 `created|updated|deleted`；`category` 为 `relationship|source|configuration`。一个对象 epoch 最多产生一条消息；同时包含多种字段时按 relationship、source、configuration 的优先级分类。按时间降序排列，同一时间以 epoch sequence 和不可变 epoch ID 稳定排序；分页总数在权限过滤后计算。分页期间发生新的提交时，offset 会随最新结果移动。

消息由既有 `enerCubixMeterEpoch` 的相邻配置前后值投影，目前覆盖其已追踪的表计、传感器、分类、分项、公式、清洗方案、组织和空间。初始化快照不作为用户操作，同值及仅敏感／非重要字段变化不产生消息。新提交在 epoch 的独立 `enerCubixEpochActor` 标签记录当前 FIN 用户名；旧日志缺少操作者时不返回 actor，也不从配置推断。操作者与初始化标记不进入计算配置。

仅返回白名单：当前归属引用、主点／公式绑定、公式与变量、对象名称／类型、autoSum、includeInTotals、historyMode、maximum、unit、清洗开关／方案／模式及受支持 parameters、报警开关／阈值。parameters 仅保留既有清洗参数名及受支持数值／单位结构，alarmLimits 仅保留 categoryId 与 limit；密码、令牌、凭据和整份旧配置不返回。

当前无权读取的对象不返回消息；当前已删除对象的日志仅管理员可见。历史引用按当前对象权限重新检查，包括旧父引用、公式 variables、alarmLimits 内引用；失效、无权或不支持的嵌套引用字段整项省略，并返回 `detailsRestricted:true`，不暴露引用 ID、缓存名称或部分旧值。单条损坏 epoch 仅记服务端通用告警；其后的未知旧值不冒充新建或已知变更，后续有效快照重新建立比较基线。消息投影不被报告、选表或虚拟表计算使用。
