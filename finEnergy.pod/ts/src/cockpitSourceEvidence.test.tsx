import {expect,it} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {CockpitSourceEvidence} from './CockpitSourceEvidence';
import type {CockpitSnapshot} from './cockpitTypes';
import type {ReportSnapshot} from './types';
it('does not construct closed source tables or cleaning JSON before the first expansion',()=>{
 const snapshot={snapshotId:'evidence-test',provenance:{appliedCleaning:[{privateDetail:'not-mounted'}]}} as unknown as CockpitSnapshot;
 const report={result:{series:[{points:[{ts:'eager-row'}]}]}} as unknown as ReportSnapshot;
 const html=renderToStaticMarkup(<CockpitSourceEvidence snapshot={snapshot} report={report}/>);
 expect(html).toContain('cockpit-source-evidence');expect(html).not.toContain('eager-row');expect(html).not.toContain('not-mounted');expect(html).not.toContain('<table');expect(html).not.toContain('<pre');
});
