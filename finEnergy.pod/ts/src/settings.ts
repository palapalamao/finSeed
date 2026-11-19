import type {FinEnergyRecord} from './types';

export function meterRollupSeconds(records:FinEnergyRecord[]):number{
 const value=records.find(row=>row.kind==='settings')?.meterRollupSeconds;
 return typeof value==='number'?value:1;
}
