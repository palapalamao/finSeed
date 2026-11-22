import {Alert, Button} from 'antd';
import {useEffect, useState} from 'react';
import {t} from './i18n';
import {queryBudgetMs} from './queryPerformance';

export function QueryWaitStatus({startedAt, phase, onCancel}: {
  startedAt: number;
  phase: string;
  onCancel: () => void;
}) {
  const [now, setNow] = useState(() => performance.now());
  useEffect(() => {
    const update = () => setNow(performance.now());
    update();
    const timer = window.setInterval(update, 500);
    return () => window.clearInterval(timer);
  }, [startedAt]);
  const elapsed = now - startedAt;
  if (elapsed <= queryBudgetMs) return null;
  return <Alert
    className="report-warning"
    type="warning"
    showIcon
    message={t('已等待 {0} 秒，超过 11 秒查询目标。', Math.floor(elapsed / 1000))}
    description={phase}
    action={<Button onClick={onCancel}>{t('取消查询')}</Button>}
  />;
}
