import {t,subscribeLocale} from './i18n';
import cube from '../../res/finenergy-cube.webp?url';

export let productName=t('FIN 能源管理');
export let productTagline=t('楼宇能源分析');
subscribeLocale(()=>{productName=t('FIN 能源管理');productTagline=t('楼宇能源分析');});

/** Temporary product symbol, pending the official FIN Energy identity. */
export function BrandMark(){
 return <img className="brand-mark" src={cube} alt="" aria-hidden="true" width={44} height={44}/>;
}
