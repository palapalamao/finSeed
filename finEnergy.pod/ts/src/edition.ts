declare const __FIN_ENERGY_CHINA__: boolean;

export const chinaBuild = typeof __FIN_ENERGY_CHINA__ !== 'undefined' && __FIN_ENERGY_CHINA__;
export const editionLabel = chinaBuild ? '中国版' : '总部版';
export const licenseModeLabel = chinaBuild ? '自有授权' : 'FIN 原生授权';
