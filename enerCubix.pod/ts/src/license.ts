export type LicenseKind='host'|'training';
export type LicenseState='trial'|'active'|'expired'|'invalid'|'notYetValid'|'hostUnavailable';

export interface LicenseStatus {
 status:LicenseState;
 used:number;
 limit:number|null;
 overLimit:boolean;
 canImport:boolean;
 hostId?:string|null;
 licenseType?:LicenseKind|null;
 licenseId?:string|null;
 notBefore?:string|null;
 expiresAt?:string|null;
}

export const maxLicenseFileBytes=16*1024;

export function createLicenseRequest(hostId:string,now=new Date()){
 return {version:1,product:'enerCubix',hostId,requestedAt:now.toISOString()};
}
