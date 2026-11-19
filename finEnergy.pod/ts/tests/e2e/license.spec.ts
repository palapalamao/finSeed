import { readFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import type { LicenseStatus } from '../../src/license';
import { installTransport, openView } from './fixtures';

test('FIN superuser exports a machine request and activates a training license', async ({ page }) => {
  await installTransport(page, { userLocale: 'zh-CN' });
  const hostId = 'TEST-HOST-ID';
  const trial: LicenseStatus = { status: 'trial', used: 11, limit: 10, overLimit: true, canImport: true, hostId };
  const active: LicenseStatus = {
    ...trial, status: 'active', limit: null, overLimit: false, licenseType: 'training',
    notBefore: '2026-11-13T01:00:00Z', expiresAt: '2026-11-13T13:00:00Z',
  };
  await page.route('**/v1/license/status', route => route.fulfill({ json: { ok: true, data: trial } }));
  await page.route('**/v1/license/import', route => {
    if (route.request().postDataJSON().license === 'signed-training-fixture') {
      return route.fulfill({ json: { ok: true, data: active } });
    }
    return route.fulfill({ status: 400, json: { ok: false, error: { code: 'LICENSE_INVALID', msg: 'licenseInvalid' } } });
  });

  await openView(page, 'license');
  await expect(page.getByRole('heading', { name: '授权管理', exact: true })).toBeVisible();
  await expect(page.getByText('项目已超出免费额度', { exact: true })).toBeVisible();
  await expect(page.getByText('11 / 10 块', { exact: true })).toBeVisible();
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: '导出授权申请' }).click();
  const download = await downloadPromise;
  const filePath = await download.path();
  expect(download.suggestedFilename()).toBe('finenergy-request.json');
  expect(JSON.parse(await readFile(filePath!, 'utf8'))).toEqual({
    version: 1, product: 'finEnergy', hostId, requestedAt: expect.any(String),
  });

  const fileInput = page.locator('input[type=file]');
  const importButton = page.getByRole('button', { name: '导入授权文件' });
  await page.getByRole('button', { name: '添加授权', exact: true }).click();
  await expect(page.getByRole('dialog', { name: '添加授权' })).toBeVisible();
  await fileInput.setInputFiles({ name: 'training.json', mimeType: 'application/json', buffer: Buffer.from('signed-training-fixture') });
  await importButton.click();
  await expect(page.getByText('培训授权', { exact: true })).toBeVisible();
  await expect(page.getByText('11 块 · 无上限', { exact: true })).toBeVisible();
  await expect(page.getByText('项目已超出免费额度', { exact: true })).toBeHidden();

  await page.getByRole('button', { name: '添加授权', exact: true }).click();
  await fileInput.setInputFiles({ name: 'tampered.json', mimeType: 'application/json', buffer: Buffer.from('tampered') });
  await importButton.click();
  await expect(page.getByText('11 块 · 无上限', { exact: true })).toBeVisible();
  await expect(page.getByRole('dialog').locator('.ant-alert-error')).toBeVisible();
});

test('project administrators see the English mobile license page with no import action', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await installTransport(page, { userLocale: 'en-US' });
  await page.route('**/v1/license/status', route => route.fulfill({
    json: { ok: true, data: { status: 'expired', used: 10, limit: 10, overLimit: false, canImport: false,
      hostId: 'LONG-FIN-MACHINE-CODE-FOR-MOBILE-TEST-00001-ABCDE-ABCDE', licenseType: 'host',
      expiresAt: '2026-11-13T13:00:00Z' } satisfies LicenseStatus },
  }));
  await openView(page, 'license');
  await expect(page.getByRole('heading', { name: 'License management', exact: true })).toBeVisible();
  await expect(page.getByText('License expired', { exact: true })).toBeVisible();
  await expect(page.getByText('Machine-bound license', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Export license request' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Add license', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Delete license', exact: true })).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

test('superuser cancels or confirms deleting the current license on English mobile', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await installTransport(page, { userLocale: 'en-US' });
  const active: LicenseStatus = { status: 'active', used: 11, limit: null, overLimit: false,
    canImport: true, canDelete: true, deleteToken: 'current-license-token', licenseType: 'host' };
  const trial: LicenseStatus = { status: 'trial', used: 11, limit: 10, overLimit: true,
    canImport: true, canDelete: false };
  const submitted: unknown[] = [];
  await page.route('**/v1/license/status', route => route.fulfill({ json: { ok: true, data: active } }));
  await page.route('**/v1/license/delete', route => {
    submitted.push(route.request().postDataJSON());
    return route.fulfill({ json: { ok: true, data: trial } });
  });

  await openView(page, 'license');
  const deleteButton = page.getByRole('button', { name: 'Delete license', exact: true });
  const confirmation = page.getByRole('dialog', { name: 'Confirm license deletion' });
  await deleteButton.click();
  await expect(confirmation.getByText(/each project on this FIN instance/)).toBeVisible();
  await confirmation.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(confirmation).toBeHidden();
  expect(submitted).toHaveLength(0);

  await deleteButton.click();
  await confirmation.getByRole('button', { name: 'Delete license', exact: true }).click();
  await expect(page.getByText('11 / 10 meters', { exact: true })).toBeVisible();
  await expect(page.getByText('This project exceeds its free meter allowance', { exact: true })).toBeVisible();
  await expect(deleteButton).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Add license', exact: true })).toBeVisible();
  expect(submitted).toEqual([{ token: 'current-license-token' }]);
});
