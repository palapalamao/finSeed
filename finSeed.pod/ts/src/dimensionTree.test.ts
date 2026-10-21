import {describe,it,expect} from 'vitest';
import {canonicalMeters,dimensionBranch,dimensionPath,dimensionRecords,dimensionRoots,dimensionScope,isMeter,meterDetailCounts,moveTargets,pointBindingPlan} from './dimensionTree';
import {reportDimension,type SeedRecord} from './types';
const records:SeedRecord[]=[
 {id:'s',kind:'space',name:'园区'},{id:'f',kind:'space',name:'一层',parentId:'s'},
 {id:'o',kind:'organization',name:'后勤'},{id:'d',kind:'organization',name:'维修',parentId:'o'},
 {id:'master',kind:'totalMeter',name:'总电表',spaceId:'s',organizationId:'o',pointId:'p0'},
 {id:'m',kind:'meter',name:'照明',spaceId:'f',organizationId:'d',meterParentId:'master',pointId:'p1'},
 {id:'alias',kind:'meter',name:'旧树照明',canonicalId:'m',parentId:'g',pointId:'p1'},
 {id:'free',kind:'meter',name:'待归属',pointId:'p2'},
 {id:'g',kind:'group',name:'旧分组'},
];
describe('three independent views of canonical meters',()=>{
 it('shows physical topology and completion counts independent of the current view',()=>{expect(meterDetailCounts(records,'master')).toEqual({direct:1,descendants:1,bound:2,unfinished:2});});
 it('keeps COP legacy semantics while other reports retain their chosen dimension',()=>{for(const dimension of ['space','metering','organization','legacy']as const){expect(reportDimension('cop',dimension)).toBe('legacy');expect(reportDimension('profile',dimension)).toBe(dimension);}});
 it('keeps the same meter id and hides compatibility aliases in all new views',()=>{
  expect(canonicalMeters(records).map(r=>r.id)).toEqual(['master','m','free']);
  for(const dimension of ['space','metering','organization']as const){const flatten=(rows:ReturnType<typeof dimensionRoots>):string[]=>rows.flatMap(r=>[r.key,...flatten(r.children)]);const ids=flatten(dimensionRoots(records,dimension));expect(ids.filter(id=>id==='m')).toHaveLength(1);expect(ids).not.toContain('alias');}
 });
 it('groups metering roots under synthetic category folders without changing reportable ids',()=>{const data=dimensionRoots([...records.map(row=>row.id==='master'||row.id==='m'?{...row,categoryId:'electric'}:row),{id:'electric',kind:'category',name:'电',unit:'kWh'}],'metering');const folder=data.find(row=>row.title==='电');expect(folder?.synthetic).toBe(true);expect(folder?.record).toBeUndefined();expect(folder?.children[0].key).toBe('master');expect(dimensionScope(records,undefined,'metering','children').map(row=>row.id)).toEqual(['master']);});
 it('follows only the selected relation when scoping and building provenance',()=>{
  expect([...dimensionBranch(records,'s','space')]).toEqual(['s','f','master','m']);
  expect([...dimensionBranch(records,'master','metering')]).toEqual(['master','m']);
  expect(dimensionPath(records,'m','space').map(r=>r.id)).toEqual(['s','f','m']);
  expect(dimensionPath(records,'m','organization').map(r=>r.id)).toEqual(['o','d','m']);
  expect(dimensionScope(records,'s','space','children').map(r=>r.id)).toEqual(['f','master']);
  expect(dimensionScope(records,'s','space','branch').map(r=>r.id)).toEqual(['f','master','m']);
 });
 it('exposes missing assignments and excludes descendants from move targets',()=>{
  const root=dimensionRoots(records,'space').find(r=>r.bucket);expect(root?.children.map(r=>r.key)).toEqual(['free']);
  expect(moveTargets(records,['s'],'space').map(r=>r.id)).toEqual([]);
  expect(moveTargets(records,['master'],'metering').map(r=>r.id)).toEqual(['free']);
 });
 it('bounds broken cycles and still exposes every record',()=>{
  const broken=[{id:'a',kind:'space',name:'a',parentId:'b'},{id:'b',kind:'space',name:'b',parentId:'a'}]as SeedRecord[];
  expect(dimensionPath(broken,'a','space')).toHaveLength(2);expect(dimensionRoots(broken,'space').find(r=>r.bucket)?.children).toHaveLength(2);
 });
 it('reuses an existing physical point through its canonical record',()=>{
  const plan=pointBindingPlan(records,[{id:'p1',name:'照明',his:true},{id:'p3',name:'新点',his:true}]);
  expect(plan.reuse.map(r=>r.id)).toEqual(['m']);expect(plan.create.map(r=>r.id)).toEqual(['p3']);
 });
});
describe('live FIN space projection',()=>{
 const native:SeedRecord[]=[
  {id:'archive',kind:'meter',name:'照明档案',pointId:'point',spaceId:'old',nativeSpaceId:'equip',nativeSpaceReadonly:true,meterParentId:'master',organizationId:'org'},
  {id:'virtual',kind:'meter',name:'虚拟档案',expressionId:'expression'},{id:'old',kind:'space',name:'旧手工空间',nativeHidden:true},
  {id:'master',kind:'totalMeter',name:'总表'},{id:'org',kind:'organization',name:'后勤'},
  {id:'site',kind:'space',name:'FIN 站点',nativeReadonly:true,nativeSourceKind:'site'},
  {id:'floor',kind:'space',name:'FIN 楼层',parentId:'site',nativeReadonly:true,nativeSourceKind:'floor'},
  {id:'equip',kind:'space',name:'FIN 设备',parentId:'floor',nativeReadonly:true,nativeSourceKind:'equip'},
  {id:'raw',kind:'nativePoint',name:'温度',parentId:'equip',nativeReadonly:true,nativeSourceId:'raw',unit:'°C',his:true},
  {id:'point',kind:'nativePoint',name:'累计电量',parentId:'equip',nativeReadonly:true,nativeSourceId:'point',his:true},
 ];
 const flatten=(rows:ReturnType<typeof dimensionRoots>):string[]=>rows.flatMap(row=>[row.key,...flatten(row.children)]);
 it('omits native points without his even when already bound to an archive',()=>{
  const changed=native.map(row=>row.id==='point'?{...row,his:false}:row.id==='raw'?{...row,his:undefined}:row);
  expect(flatten(dimensionRoots(changed,'space'))).toEqual(['site','floor','equip']);
  expect(dimensionScope(changed,'equip','space','children')).toEqual([]);
  expect(canonicalMeters(changed).map(row=>row.id)).toContain('archive');
 });
 it('keeps source order and replaces a bound leaf with its single canonical archive',()=>{
  const roots=dimensionRoots(native,'space');expect(flatten(roots)).toEqual(['site','floor','equip','raw','archive']);
  expect(dimensionRecords(native,'space').find(row=>row.id==='archive')).toMatchObject({name:'累计电量',pointId:'point',spaceId:'old',nativeSpaceId:'equip'});
  expect(canonicalMeters(native).map(row=>row.id)).toEqual(['archive','virtual','master']);expect(isMeter(native.find(row=>row.id==='raw')!)).toBe(false);
  expect(dimensionScope(native,'raw','space','children')).toEqual([]);
 });
 it('uses refreshed rename, placement and deletion while preserving metering and organization',()=>{
  const changed=native.filter(row=>row.id!=='raw').map(row=>row.id==='equip'?{...row,name:'新设备名',parentId:'site'}:row.id==='point'?{...row,name:'最新电量'}:row);
  expect(dimensionPath(changed,'archive','space').map(row=>row.name)).toEqual(['FIN 站点','新设备名','最新电量']);expect(flatten(dimensionRoots(changed,'space'))).not.toContain('raw');
  expect(dimensionPath(changed,'archive','metering').map(row=>row.id)).toEqual(['master','archive']);expect(dimensionPath(changed,'archive','organization').map(row=>row.id)).toEqual(['org','archive']);
 });
 it('retains configured space semantics only when a historical request opts out',()=>{
  expect(dimensionPath(native,'archive','space',false).map(row=>row.id)).toEqual(['old','archive']);expect(dimensionPath(native,'archive','space').map(row=>row.id)).toEqual(['site','floor','equip','archive']);
  expect(pointBindingPlan(native,[{id:'point',name:'累计电量',his:true}]).reuse.map(row=>row.id)).toEqual(['archive']);
 });
 it('does not add missing or virtual archives as synthetic FIN tree branches',()=>{
  expect(flatten(dimensionRoots(native.filter(row=>row.id!=='point'),'space'))).not.toContain('archive');expect(dimensionRoots(native,'space').some(row=>row.bucket)).toBe(false);
 });
});
