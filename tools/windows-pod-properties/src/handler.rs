use crate::metadata::read_metadata;
use std::ffi::c_void;
use std::io::{self, Read, Seek, SeekFrom};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Mutex,
};
use windows::core::{implement, w, Error, IUnknown, Interface, Ref, Result, GUID, HRESULT, PWSTR};
use windows::Win32::Foundation::*;
use windows::Win32::System::Com::StructuredStorage::PROPVARIANT;
use windows::Win32::System::Com::*;
use windows::Win32::System::Variant::VT_LPWSTR;
use windows::Win32::UI::Shell::PropertiesSystem::*;

pub const CLSID: GUID = GUID::from_u128(0x177765e4_6e21_4c9b_9ec0_dd3b108543b8);
pub const CUSTOM: GUID = GUID::from_u128(0x36ce443d_5bf0_4c59_a51f_8337390063a1);
static OBJECTS: AtomicUsize = AtomicUsize::new(0);
static LOCKS: AtomicUsize = AtomicUsize::new(0);

struct Lifetime;
impl Lifetime {
    fn new() -> Self {
        OBJECTS.fetch_add(1, Ordering::SeqCst);
        Self
    }
}
impl Drop for Lifetime {
    fn drop(&mut self) {
        OBJECTS.fetch_sub(1, Ordering::SeqCst);
    }
}

struct StreamReader(IStream);
impl Read for StreamReader {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        let mut count = 0;
        unsafe {
            self.0
                .Read(
                    bytes.as_mut_ptr().cast(),
                    bytes.len().min(u32::MAX as usize) as u32,
                    Some(&mut count),
                )
                .ok()
        }
        .map_err(io::Error::other)?;
        Ok(count as usize)
    }
}
impl Seek for StreamReader {
    fn seek(&mut self, at: SeekFrom) -> io::Result<u64> {
        let (distance, origin) = match at {
            SeekFrom::Start(n) => (i64::try_from(n).map_err(io::Error::other)?, STREAM_SEEK_SET),
            SeekFrom::Current(n) => (n, STREAM_SEEK_CUR),
            SeekFrom::End(n) => (n, STREAM_SEEK_END),
        };
        let mut position = 0;
        unsafe { self.0.Seek(distance, origin, Some(&mut position)) }.map_err(io::Error::other)?;
        Ok(position)
    }
}

#[implement(IPropertyStore, IPropertyStoreCapabilities, IInitializeWithStream)]
struct Handler {
    properties: Mutex<Option<Vec<(PROPERTYKEY, String)>>>,
    _lifetime: Lifetime,
}
impl Handler {
    fn new() -> Self {
        Self {
            properties: Mutex::new(None),
            _lifetime: Lifetime::new(),
        }
    }
}
impl IInitializeWithStream_Impl for Handler_Impl {
    fn Initialize(&self, stream: Ref<'_, IStream>, mode: u32) -> Result<()> {
        if mode & 3 != 0 {
            return Err(STG_E_ACCESSDENIED.into());
        }
        let mut state = self.properties.lock().map_err(|_| Error::from(E_FAIL))?;
        if state.is_some() {
            return Err(HRESULT(0x800704dfu32 as i32).into());
        }
        let input = stream.as_ref().ok_or_else(|| Error::from(E_POINTER))?;
        let metadata = read_metadata(&mut StreamReader(input.clone()))
            .map_err(|_| Error::from(STG_E_INVALIDHEADER))?;
        let mut product = PROPERTYKEY::default();
        let mut version = PROPERTYKEY::default();
        unsafe {
            PSGetPropertyKeyFromName(w!("System.Software.ProductName"), &mut product)?;
            PSGetPropertyKeyFromName(w!("System.Software.ProductVersion"), &mut version)?;
        }
        let edition = if metadata.edition == "china" {
            "中国版 / China"
        } else {
            "总部版 / HQ"
        };
        let mut values = vec![
            (product, "FIN Energy".to_owned()),
            (version, metadata.version),
            (
                PROPERTYKEY {
                    fmtid: CUSTOM,
                    pid: 2,
                },
                edition.to_owned(),
            ),
        ];
        if let Some(mode) = metadata.license_mode {
            let label = if mode == "selfManaged" {
                "独立授权 / Self-managed"
            } else {
                "FIN 原生授权 / FIN native"
            };
            values.push((
                PROPERTYKEY {
                    fmtid: CUSTOM,
                    pid: 3,
                },
                label.to_owned(),
            ));
        }
        *state = Some(values);
        Ok(())
    }
}
impl IPropertyStore_Impl for Handler_Impl {
    fn GetCount(&self) -> Result<u32> {
        let state = self.properties.lock().map_err(|_| Error::from(E_FAIL))?;
        Ok(state.as_ref().map_or(0, |p| p.len() as u32))
    }
    fn GetAt(&self, index: u32, key: *mut PROPERTYKEY) -> Result<()> {
        if key.is_null() {
            return Err(E_POINTER.into());
        }
        let state = self.properties.lock().map_err(|_| Error::from(E_FAIL))?;
        let value = state
            .as_ref()
            .and_then(|p| p.get(index as usize))
            .ok_or_else(|| Error::from(E_INVALIDARG))?;
        unsafe {
            *key = value.0;
        }
        Ok(())
    }
    fn GetValue(&self, key: *const PROPERTYKEY) -> Result<PROPVARIANT> {
        if key.is_null() {
            return Err(E_POINTER.into());
        }
        let state = self.properties.lock().map_err(|_| Error::from(E_FAIL))?;
        let value = state
            .as_ref()
            .and_then(|p| p.iter().find(|p| unsafe { p.0 == *key }));
        let Some((_, value)) = value else {
            return Ok(PROPVARIANT::default());
        };
        let utf16: Vec<u16> = value.encode_utf16().chain(Some(0)).collect();
        let mut result = PROPVARIANT::default();
        unsafe {
            let buffer = CoTaskMemAlloc(utf16.len() * 2).cast::<u16>();
            if buffer.is_null() {
                return Err(E_OUTOFMEMORY.into());
            }
            std::ptr::copy_nonoverlapping(utf16.as_ptr(), buffer, utf16.len());
            let inner = &mut *result.Anonymous.Anonymous;
            inner.vt = VT_LPWSTR;
            inner.Anonymous.pwszVal = PWSTR(buffer);
        }
        Ok(result)
    }
    fn SetValue(&self, _: *const PROPERTYKEY, _: *const PROPVARIANT) -> Result<()> {
        Err(STG_E_ACCESSDENIED.into())
    }
    fn Commit(&self) -> Result<()> {
        Err(STG_E_ACCESSDENIED.into())
    }
}
impl IPropertyStoreCapabilities_Impl for Handler_Impl {
    fn IsPropertyWritable(&self, _: *const PROPERTYKEY) -> HRESULT {
        S_FALSE
    }
}

#[implement(IClassFactory)]
struct Factory {
    _lifetime: Lifetime,
}
impl IClassFactory_Impl for Factory_Impl {
    fn CreateInstance(
        &self,
        outer: Ref<'_, IUnknown>,
        iid: *const GUID,
        result: *mut *mut c_void,
    ) -> Result<()> {
        if iid.is_null() || result.is_null() {
            return Err(E_POINTER.into());
        }
        unsafe {
            *result = std::ptr::null_mut();
        }
        if outer.is_some() {
            return Err(CLASS_E_NOAGGREGATION.into());
        }
        let object: IUnknown = Handler::new().into();
        unsafe { object.query(iid, result).ok() }
    }
    fn LockServer(&self, lock: windows::core::BOOL) -> Result<()> {
        if lock.as_bool() {
            LOCKS.fetch_add(1, Ordering::SeqCst);
        } else {
            let _ = LOCKS.fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1));
        }
        Ok(())
    }
}

#[no_mangle]
pub unsafe extern "system" fn DllGetClassObject(
    class: *const GUID,
    iid: *const GUID,
    result: *mut *mut c_void,
) -> HRESULT {
    if class.is_null() || iid.is_null() || result.is_null() {
        return E_POINTER;
    }
    *result = std::ptr::null_mut();
    if *class != CLSID {
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    let factory: IUnknown = Factory {
        _lifetime: Lifetime::new(),
    }
    .into();
    factory.query(iid, result)
}

#[no_mangle]
pub extern "system" fn DllCanUnloadNow() -> HRESULT {
    if OBJECTS.load(Ordering::SeqCst) == 0 && LOCKS.load(Ordering::SeqCst) == 0 {
        S_OK
    } else {
        S_FALSE
    }
}
