import {t,subscribeLocale} from './i18n';

export let productName=t('FIN Energy 能源管理');
export let productTagline=t('楼宇能源分析');
subscribeLocale(()=>{productName=t('FIN Energy 能源管理');productTagline=t('楼宇能源分析');});

/** Temporary product symbol, pending the official FIN Energy identity. */
export function BrandMark(){
 return <svg className="brand-mark" viewBox="0 0 44 44" fill="none" aria-hidden="true">
  <rect x="2" y="2" width="40" height="40" rx="9" fill="#0e2738"/>
  <path d="M12 29V21M22 29V15M32 29V10" stroke="#00ccff" strokeWidth="4" strokeLinecap="round"/>
  <path d="M11 34H33" stroke="#ffffff" strokeWidth="2" strokeLinecap="round"/>
 </svg>;
}
