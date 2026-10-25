import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';

for(const mobile of [false,true])test('analysis topics expose existing reports on '+(mobile?'mobile':'desktop'),async({page},testInfo)=>{
 if(mobile)await page.setViewportSize({width:390,height:844});
 await installTransport(page);await openView(page,'primary');
 for(const name of ['趋势与负荷','构成与排名','对比分析','效率与折算','差额与预测'])await expect(page.getByRole('tab',{name,exact:true}).first()).toBeVisible();
 for(const name of (mobile?['一次能源分析']:['COP 分析','一次能源分析','工作时段分析','工作日分析']))await expect(page.getByRole('tab',{name,exact:true})).toBeVisible();
 await page.getByRole('tab',{name:'差额与预测',exact:true}).click();
 await page.getByRole('tab',{name:'能耗预测',exact:true}).click();await expect(page.getByRole('heading',{name:'能耗预测',exact:true})).toBeVisible();
 await page.screenshot({path:testInfo.outputPath('analysis-navigation-'+(mobile?'mobile':'desktop')+'.png'),fullPage:true});
 for(const [view,title]of [['workingHours','工作时段分析'],['workingDays','工作日分析']]){await page.goto('/#/'+view+'?project=testproject');await expect(page.getByRole('heading',{name:title,exact:true})).toBeVisible();}
});
