use std::io::{self, Read, Seek, SeekFrom};

const MAX_DIRECTORY: usize = 4 * 1024 * 1024;
const MAX_METADATA: usize = 64 * 1024;

#[derive(Debug)]
pub struct Metadata {
    pub version: String,
    pub edition: String,
    pub license_mode: Option<String>,
}

fn invalid() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        "Unsupported or malformed FIN Energy Pod",
    )
}
fn u16_at(bytes: &[u8], at: usize) -> io::Result<u16> {
    Ok(u16::from_le_bytes(
        bytes
            .get(at..at + 2)
            .ok_or_else(invalid)?
            .try_into()
            .unwrap(),
    ))
}
fn u32_at(bytes: &[u8], at: usize) -> io::Result<u32> {
    Ok(u32::from_le_bytes(
        bytes
            .get(at..at + 4)
            .ok_or_else(invalid)?
            .try_into()
            .unwrap(),
    ))
}

/// Read only the end record, bounded central directory and exact meta.props member.
/// No member is extracted to disk, loaded as code, or read through an archive path.
pub fn read_metadata(input: &mut (impl Read + Seek)) -> io::Result<Metadata> {
    let length = input.seek(SeekFrom::End(0))?;
    if !(22..=1024 * 1024 * 1024).contains(&length) {
        return Err(invalid());
    }
    let tail_len = length.min(65557) as usize;
    input.seek(SeekFrom::End(-(tail_len as i64)))?;
    let mut tail = vec![0; tail_len];
    input.read_exact(&mut tail)?;
    let end = (0..=tail_len - 22)
        .rev()
        .find(|&i| {
            tail[i..i + 4] == [0x50, 0x4b, 0x05, 0x06]
                && i + 22 + u16::from_le_bytes([tail[i + 20], tail[i + 21]]) as usize == tail_len
        })
        .ok_or_else(invalid)?;
    let count = u16_at(&tail, end + 10)? as usize;
    let size = u32_at(&tail, end + 12)? as usize;
    let start = u32_at(&tail, end + 16)? as u64;
    let absolute_end = length - tail_len as u64 + end as u64;
    if count == 0
        || count > 8192
        || size > MAX_DIRECTORY
        || u16_at(&tail, end + 4)? != 0
        || u16_at(&tail, end + 6)? != 0
        || u16_at(&tail, end + 8)? as usize != count
        || start + size as u64 != absolute_end
    {
        return Err(invalid());
    }
    input.seek(SeekFrom::Start(start))?;
    let mut directory = vec![0; size];
    input.read_exact(&mut directory)?;
    let mut position = 0;
    let mut member = None;
    for _ in 0..count {
        if u32_at(&directory, position)? != 0x02014b50 {
            return Err(invalid());
        }
        let name_len = u16_at(&directory, position + 28)? as usize;
        let extra_len = u16_at(&directory, position + 30)? as usize;
        let comment_len = u16_at(&directory, position + 32)? as usize;
        if name_len > 1024 || extra_len > 4096 || comment_len > 4096 {
            return Err(invalid());
        }
        let end = position + 46 + name_len + extra_len + comment_len;
        let name = directory
            .get(position + 46..position + 46 + name_len)
            .ok_or_else(invalid)?;
        if end > directory.len() {
            return Err(invalid());
        }
        if name == b"meta.props" {
            if member.is_some() {
                return Err(invalid());
            }
            let flags = u16_at(&directory, position + 8)?;
            let method = u16_at(&directory, position + 10)?;
            let compressed = u32_at(&directory, position + 20)? as usize;
            let unpacked = u32_at(&directory, position + 24)? as usize;
            let offset = u32_at(&directory, position + 42)? as u64;
            if flags & !0x0808 != 0
                || ![0, 8].contains(&method)
                || compressed == 0
                || compressed > MAX_METADATA
                || unpacked == 0
                || unpacked > MAX_METADATA
                || u16_at(&directory, position + 34)? != 0
                || offset + 30 > start
            {
                return Err(invalid());
            }
            member = Some((
                offset,
                compressed,
                unpacked,
                method,
                u32_at(&directory, position + 16)?,
                flags,
            ));
        }
        position = end;
    }
    if position != directory.len() {
        return Err(invalid());
    }
    let (offset, compressed, unpacked, method, crc, flags) = member.ok_or_else(invalid)?;
    input.seek(SeekFrom::Start(offset))?;
    let mut local = [0; 30];
    input.read_exact(&mut local)?;
    let extra = u16_at(&local, 28)? as u64;
    if u32_at(&local, 0)? != 0x04034b50
        || u16_at(&local, 6)? != flags
        || u16_at(&local, 8)? != method
        || u16_at(&local, 26)? != 10
        || extra > 4096
        || offset + 40 + extra + compressed as u64 > start
    {
        return Err(invalid());
    }
    let mut name = [0; 10];
    input.read_exact(&mut name)?;
    if &name != b"meta.props" {
        return Err(invalid());
    }
    input.seek(SeekFrom::Current(extra as i64))?;
    let mut packed = vec![0; compressed];
    input.read_exact(&mut packed)?;
    let bytes = if method == 0 {
        packed
    } else {
        let mut decoder = flate2::read::DeflateDecoder::new(packed.as_slice());
        let mut bytes = Vec::new();
        (&mut decoder)
            .take((MAX_METADATA + 1) as u64)
            .read_to_end(&mut bytes)?;
        if decoder.total_in() != compressed as u64 {
            return Err(invalid());
        }
        bytes
    };
    if bytes.len() != unpacked || crc32fast::hash(&bytes) != crc {
        return Err(invalid());
    }
    parse_properties(&bytes)
}

fn parse_properties(bytes: &[u8]) -> io::Result<Metadata> {
    let text = std::str::from_utf8(bytes).map_err(|_| invalid())?;
    if text.contains('\0') {
        return Err(invalid());
    }
    let mut fields = std::collections::BTreeMap::new();
    for line in text.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        if ![
            "pod.name",
            "pod.version",
            "finEnergy.edition",
            "finEnergy.licenseMode",
        ]
        .contains(&key)
        {
            continue;
        }
        let value = value.trim();
        if value.len() > 128 || !value.is_ascii() || fields.insert(key, value).is_some() {
            return Err(invalid());
        }
    }
    if fields.get("pod.name") != Some(&"finEnergy") {
        return Err(invalid());
    }
    let version = *fields.get("pod.version").ok_or_else(invalid)?;
    let parts: Vec<_> = version.split('.').collect();
    if !(3..=4).contains(&parts.len())
        || parts
            .iter()
            .any(|p| p.is_empty() || p.len() > 9 || !p.bytes().all(|c| c.is_ascii_digit()))
    {
        return Err(invalid());
    }
    let edition = *fields.get("finEnergy.edition").ok_or_else(invalid)?;
    if !["china", "hq"].contains(&edition) {
        return Err(invalid());
    }
    let mode = fields.get("finEnergy.licenseMode").copied();
    if let Some(mode) = mode {
        if mode
            != if edition == "china" {
                "selfManaged"
            } else {
                "finNative"
            }
        {
            return Err(invalid());
        }
    }
    Ok(Metadata {
        version: version.into(),
        edition: edition.into(),
        license_mode: mode.map(String::from),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Cursor, Write};

    fn archive(name: &str, data: &[u8], method: u16) -> Vec<u8> {
        let packed = if method == 8 {
            let mut encoder =
                flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::default());
            encoder.write_all(data).unwrap();
            encoder.finish().unwrap()
        } else {
            data.to_vec()
        };
        let mut bytes = Vec::new();
        let crc = crc32fast::hash(data);
        bytes.extend(0x04034b50u32.to_le_bytes());
        bytes.extend(20u16.to_le_bytes());
        bytes.extend(0u16.to_le_bytes());
        bytes.extend(method.to_le_bytes());
        bytes.extend([0; 4]);
        bytes.extend(crc.to_le_bytes());
        bytes.extend((packed.len() as u32).to_le_bytes());
        bytes.extend((data.len() as u32).to_le_bytes());
        bytes.extend((name.len() as u16).to_le_bytes());
        bytes.extend([0; 2]);
        bytes.extend(name.as_bytes());
        bytes.extend(packed);
        let central_offset = bytes.len() as u32;
        bytes.extend(0x02014b50u32.to_le_bytes());
        bytes.extend([20, 0, 20, 0, 0, 0]);
        bytes.extend(method.to_le_bytes());
        bytes.extend([0; 4]);
        bytes.extend(crc.to_le_bytes());
        bytes.extend(((bytes.len() - central_offset as usize) as u32).to_le_bytes());
        // Replace the compressed size with the value from the local header.
        let packed_len = u32::from_le_bytes(bytes[18..22].try_into().unwrap());
        let central_size_field = central_offset as usize + 20;
        bytes[central_size_field..central_size_field + 4]
            .copy_from_slice(&packed_len.to_le_bytes());
        bytes.extend((data.len() as u32).to_le_bytes());
        bytes.extend((name.len() as u16).to_le_bytes());
        bytes.extend([0; 16]);
        bytes.extend(name.as_bytes());
        let central_size = bytes.len() as u32 - central_offset;
        bytes.extend(0x06054b50u32.to_le_bytes());
        bytes.extend([0; 4]);
        bytes.extend(1u16.to_le_bytes());
        bytes.extend(1u16.to_le_bytes());
        bytes.extend(central_size.to_le_bytes());
        bytes.extend(central_offset.to_le_bytes());
        bytes.extend([0; 2]);
        bytes
    }

    #[test]
    fn reads_stored_and_deflated_metadata() {
        let text = b"pod.name=finEnergy\npod.version=0.17.0.1\nfinEnergy.edition=china\nfinEnergy.licenseMode=selfManaged\n";
        for method in [0, 8] {
            let metadata =
                read_metadata(&mut Cursor::new(archive("meta.props", text, method))).unwrap();
            assert_eq!(metadata.version, "0.17.0.1");
            assert_eq!(metadata.edition, "china");
            assert_eq!(metadata.license_mode.as_deref(), Some("selfManaged"));
        }
    }

    #[test]
    fn accepts_optional_mode_and_rejects_other_products_and_conflicts() {
        assert!(parse_properties(
            b"pod.name=finEnergy\npod.version=0.17.0.2\nfinEnergy.edition=hq\n"
        )
        .is_ok());
        for text in [
            "pod.name=other\npod.version=0.17.0\nfinEnergy.edition=hq\n",
            "pod.name=finEnergy\npod.version=0.17.0\nfinEnergy.edition=unknown\n",
            "pod.name=finEnergy\npod.version=0.17.0\nfinEnergy.edition=china\nfinEnergy.licenseMode=finNative\n",
            "pod.name=finEnergy\npod.name=finEnergy\npod.version=0.17.0\nfinEnergy.edition=hq\n",
        ] { assert!(parse_properties(text.as_bytes()).is_err()); }
    }

    #[test]
    fn rejects_every_truncation_and_encrypted_metadata() {
        let data = b"pod.name=finEnergy\npod.version=0.17.0\nfinEnergy.edition=hq\n";
        let bytes = archive("meta.props", data, 8);
        for length in 0..bytes.len() {
            assert!(read_metadata(&mut Cursor::new(&bytes[..length])).is_err());
        }
        let mut encrypted = bytes.clone();
        encrypted[6] |= 1;
        let end = encrypted.len() - 22;
        let central = u32_at(&encrypted, end + 16).unwrap() as usize;
        encrypted[central + 8] |= 1;
        assert!(read_metadata(&mut Cursor::new(encrypted)).is_err());
    }

    #[test]
    fn rejects_traversal_truncation_crc_damage_and_oversized_metadata() {
        let text = b"pod.name=finEnergy\npod.version=0.17.0\nfinEnergy.edition=hq\n";
        assert!(read_metadata(&mut Cursor::new(archive("../meta.props", text, 0))).is_err());
        let mut bad = archive("meta.props", text, 0);
        bad[40] ^= 1;
        assert!(read_metadata(&mut Cursor::new(bad)).is_err());
        assert!(read_metadata(&mut Cursor::new(vec![0; 16])).is_err());
        assert!(read_metadata(&mut Cursor::new(archive(
            "meta.props",
            &vec![b'x'; 65537],
            8
        )))
        .is_err());
    }
}
