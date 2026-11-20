use std::ffi::c_void;
use windows::core::{Interface, GUID, HRESULT, HSTRING};
use windows::Win32::Foundation::*;
use windows::Win32::Storage::FileSystem::FILE_ATTRIBUTE_NORMAL;
use windows::Win32::System::Com::StructuredStorage::*;
use windows::Win32::System::Com::*;
use windows::Win32::System::LibraryLoader::*;
use windows::Win32::UI::Shell::PropertiesSystem::*;
use windows::Win32::UI::Shell::*;

const CLSID: GUID = GUID::from_u128(0x177765e4_6e21_4c9b_9ec0_dd3b108543b8);
type GetFactory = unsafe extern "system" fn(*const GUID, *const GUID, *mut *mut c_void) -> HRESULT;

unsafe fn show(store: &IPropertyStore) -> windows::core::Result<()> {
    let count = store.GetCount()?;
    println!("PropertyCount={count}");
    for index in 0..count {
        let mut key = PROPERTYKEY::default();
        store.GetAt(index, &mut key)?;
        let mut value = store.GetValue(&key)?;
        let text = PropVariantToStringAlloc(&value)?;
        println!("{:?}/{}={}", key.fmtid, key.pid, text.to_string()?);
        CoTaskMemFree(Some(text.0.cast()));
        PropVariantClear(&mut value)?;
    }
    Ok(())
}

unsafe fn run(args: &[String]) -> windows::core::Result<()> {
    CoInitializeEx(None, COINIT_APARTMENTTHREADED).ok()?;
    if args.len() == 3 && args[1] == "--registered" {
        let store: IPropertyStore =
            SHGetPropertyStoreFromParsingName(&HSTRING::from(&args[2]), None, GPS_DEFAULT)?;
        for name in [
            "System.Software.ProductName",
            "System.Software.ProductVersion",
            "FinEnergy.Edition",
            "FinEnergy.LicenseMode",
        ] {
            let mut key = PROPERTYKEY::default();
            PSGetPropertyKeyFromName(&HSTRING::from(name), &mut key)?;
            let mut value = store.GetValue(&key)?;
            let buffer = PropVariantToStringAlloc(&value)?;
            let text = buffer.to_string()?;
            CoTaskMemFree(Some(buffer.0.cast()));
            PropVariantClear(&mut value)?;
            if name != "FinEnergy.LicenseMode" && text.is_empty() {
                return Err(E_FAIL.into());
            }
            println!("{name}={text}");
        }
        return Ok(());
    }
    if args.len() != 4 || args[1] != "--direct" {
        eprintln!("Usage: inspect --direct <DLL> <Pod> | inspect --registered <Pod>");
        return Err(E_INVALIDARG.into());
    }
    // This loads the trusted handler DLL named by the developer. The Pod is
    // opened only as a read-only data stream and is never passed to LoadLibrary.
    let module = LoadLibraryExW(
        &HSTRING::from(&args[2]),
        None,
        LOAD_WITH_ALTERED_SEARCH_PATH,
    )?;
    let address = GetProcAddress(module, windows::core::s!("DllGetClassObject"))
        .ok_or_else(|| windows::core::Error::from(E_NOINTERFACE))?;
    let factory_fn: GetFactory = std::mem::transmute(address);
    let mut raw = std::ptr::null_mut();
    factory_fn(&CLSID, &IClassFactory::IID, &mut raw).ok()?;
    let factory = IClassFactory::from_raw(raw);
    let store: IPropertyStore = factory.CreateInstance(None)?;
    let initialize: IInitializeWithStream = store.cast()?;
    let stream = SHCreateStreamOnFileEx(
        &HSTRING::from(&args[3]),
        STGM_READ.0,
        FILE_ATTRIBUTE_NORMAL.0,
        false,
        None,
    )?;
    initialize.Initialize(&stream, STGM_READ.0)?;
    show(&store)?;
    let capabilities: IPropertyStoreCapabilities = store.cast()?;
    let mut first = PROPERTYKEY::default();
    store.GetAt(0, &mut first)?;
    assert_eq!(capabilities.IsPropertyWritable(&first), S_FALSE);
    assert_eq!(
        store
            .SetValue(&first, &PROPVARIANT::default())
            .unwrap_err()
            .code(),
        STG_E_ACCESSDENIED
    );
    assert_eq!(store.Commit().unwrap_err().code(), STG_E_ACCESSDENIED);
    let writing: IInitializeWithStream = factory.CreateInstance(None)?;
    assert_eq!(
        writing
            .Initialize(&stream, STGM_READWRITE.0)
            .unwrap_err()
            .code(),
        STG_E_ACCESSDENIED
    );
    println!("ReadOnlyChecks=passed");
    Ok(())
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    if let Err(error) = unsafe { run(&args) } {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
