/** FIN owns license issuance, storage, validation and expiration. */
export type LicenseState='active'|'missingFeature'|'invalid'|'inactive';
export interface LicenseStatus {
 source:'fin';
 status:LicenseState;
 feature:'fin energy';
 canManageFinLicense:boolean;
 hostId?:string;
 reason?:string;
}
