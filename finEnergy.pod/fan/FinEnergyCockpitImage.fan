using [java] javax.imageio::ImageIO
using [java] javax.imageio::ImageReader
using [java] javax.imageio.stream::MemoryCacheImageInputStream
using [java] fanx.interop::Interop

** Decode bounded PNG/JPEG pixels, then encode fresh pixels without metadata or trailing content.
internal class FinEnergyCockpitImage
{
  static const Int maxBytes := 2097152
  static const Int maxPixels := 8000000
  Buf bytes
  Str mime
  Str extension
  Int width
  Int height
  new make(Str base64)
  {
    if (base64.size > 2796204 || !Regex<|[A-Za-z0-9+/]*={0,2}|>.matches(base64) || base64.size%4 != 0) throw ArgErr("assetImageSize")
    raw:=Buf()
    try { raw=Buf.fromBase64(base64) } catch (Err e) { throw ArgErr("assetImageInvalid") }
    if (raw.size == 0 || raw.size > maxBytes) throw ArgErr("assetImageSize")
    input:=MemoryCacheImageInputStream(Interop.toJava(raw.in))
    ImageReader? reader
    try
    {
      readers:=ImageIO.getImageReaders(input)
      if (!readers.hasNext) throw ArgErr("assetImageInvalid")
      reader=(ImageReader)readers.next
      reader.setInput(input,true,true)
      format:=reader.getFormatName.lower
      if (!["png","jpeg","jpg"].contains(format)) throw ArgErr("assetImageInvalid")
      width=reader.getWidth(0); height=reader.getHeight(0)
      dimensions(width,height)
      image:=reader.read(0)
      if (image == null || image.getWidth != width || image.getHeight != height) throw ArgErr("assetImageInvalid")
      bytes=Buf(); extension=format == "png" ? "png" : "jpg"; mime=format == "png" ? "image/png" : "image/jpeg"
      if (!ImageIO.write(image,format == "png" ? "png" : "jpeg",Interop.toJava(bytes.out))) throw ArgErr("assetImageInvalid")
      bytes.flip
      if (bytes.size == 0 || bytes.size > maxBytes) throw ArgErr("assetImageSize")
    }
    catch (ArgErr e) { throw e }
    catch (Err e) { throw ArgErr("assetImageInvalid") }
    finally { reader?.dispose; input.close }
  }
  static Void dimensions(Int width, Int height)
  { if (width < 1 || height < 1 || width > 4096 || height > 4096 || width*height > maxPixels) throw ArgErr("assetImageDimensions") }
}
