## 问题与结果 / Problem and outcome

关联任务 / Related issue:

用户触发条件、修改后的行为和范围 / Trigger, resulting behavior and scope:

## 验证证据 / Verification evidence

| 层级 / Level | 版本或包哈希 / Revision or package hash | 命令或操作 / Command or action | 结果和证据 / Result and evidence |
| --- | --- | --- | --- |
| 源码检查 / Source checks | | | |
| 相关测试 / Relevant tests | | | |
| 隔离 FIN（适用时） / Isolated FIN if applicable | | | |
| 部署验证（单独记录） / Deployment verification | | | |

没有执行的检查写“未执行＋原因”；受控数据浏览器测试不代表真实 FIN 验收。
Mark checks not run with a reason; controlled-data browser tests are not FIN runtime acceptance.

## 完成条件 / Completion criteria

- [ ] 与任务验收条件一致，未混入无关改动 / Meets acceptance criteria with no unrelated changes
- [ ] 缺陷有修复前后的复现证据（适用时） / Before/after reproduction for bug fixes where applicable
- [ ] 相关测试、类型检查和构建通过，或准确说明不适用项 / Relevant tests, type check and build pass, or justified N/A
- [ ] 新增界面、图表、日期、导出和提示覆盖中英文及手机（适用时） / Applicable UI, charts, dates, exports and messages cover Chinese, English and mobile
- [ ] 历史、统计、权限或部署变更有对应专项证据（适用时） / High-risk history, calculation, permission or deployment changes have specific evidence
- [ ] 未验证事项、兼容影响和回滚办法已说明 / Verification gaps, compatibility and rollback are stated

## 发布交接 / Release handoff

候选包、版本、源码清单或哈希、依赖顺序、验证限制 / Candidate, version, source manifest/hash, dependencies and limitations:

合并状态与发布状态分别记录；发布前核对版本及包元数据。
Record merge and release separately; verify versions and package metadata before release.
