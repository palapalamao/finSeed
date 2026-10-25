import {describe,it,expect} from 'vitest';
import {filterPointRoots,finPointRoots,pointBranchKeys,type PointNode} from './pointTree';
import type {FinPoint,EnerCubixRecord} from './types';
const points:FinPoint[]=[{id:'p1',name:'电表一',navName:'电量',his:true,unit:'kWh'},{id:'p2',name:'电表二',his:true,hisStatus:'fault'},{id:'nohis',name:'实时功率',his:false}];
const records:EnerCubixRecord[]=[{id:'site',kind:'space',name:'园区',nativeReadonly:true},{id:'equip',kind:'space',name:'配电柜',parentId:'site',nativeReadonly:true},{id:'nested',kind:'space',name:'子设备',parentId:'equip',nativeReadonly:true},...points.map(point=>({id:point.id,kind:'nativePoint' as const,name:point.name,parentId:point.id==='p2'?'nested':'equip',his:point.his})),{id:'archive',kind:'meter',name:'已有档案',pointId:'p1'}];
const flatten=(nodes:PointNode[]):string[]=>nodes.flatMap(node=>[node.key,...flatten(node.children)]);
describe('FIN history point selection tree',()=>{
 it('keeps native hierarchy and raw point ids without archive overlays or ineligible leaves',()=>{
  const tree=finPointRoots(records,points,true);expect(flatten(tree)).toEqual(['site','equip','nested','p2','p1']);expect(pointBranchKeys(tree)).toEqual(['site','equip','nested']);expect(tree[0].checkable).toBe(false);
  expect(finPointRoots(records,points.map(point=>({...point,his:false})),true)).toEqual([]);
  expect(flatten(finPointRoots(records.map(row=>row.id==='p1'?{...row,his:false}:row),points,true))).not.toContain('p1');
 });
 it('searches names, ids and parent paths while retaining ancestors and clearing restores all choices',()=>{
  const tree=finPointRoots(records,points,true);expect(flatten(filterPointRoots(tree,'电表二'))).toEqual(['site','equip','nested','p2']);expect(flatten(filterPointRoots(tree,'p1'))).toEqual(['site','equip','p1']);expect(flatten(filterPointRoots(tree,'配电柜'))).toEqual(flatten(tree));expect(filterPointRoots(tree,'missing')).toEqual([]);expect(filterPointRoots(tree,'')).toBe(tree);
 });
 it('groups legacy point metadata by source ids rather than equal display names',()=>{
  const tree=finPointRoots([],points.map(point=>({...point,siteId:'s',siteName:'站点',equipId:'eq-'+point.id,equipName:'同名设备'})),false);
  expect(flatten(tree)).toEqual(['__fin:site:s','__fin:equip:eq-p1','p1','__fin:equip:eq-p2','p2']);
 });
});
