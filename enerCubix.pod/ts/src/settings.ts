import type {EnerCubixRecord} from './types';

export function meterRollupSeconds(records:EnerCubixRecord[]):number{
 const value=records.find(row=>row.kind==='settings')?.meterRollupSeconds;
 return typeof value==='number'?value:1;
}
