extends RefCounted
## Writes a tiny valid Ogg Vorbis file of silence, so the recorded-sound tests need no audio
## committed and no encoder. The stream has one codebook, one floor with no points and a
## residue that is never read: every audio packet says "this channel is silent", which a
## Vorbis decoder turns into zeros. Godot has no Vorbis encoder of its own.

const SERIAL := 0x51097
## 256-sample blocks: each audio packet after the first adds half a block.
const BLOCK_EXP := 8

var _bits := PackedByteArray()
var _bit := 0


## Silence of about `seconds` at `rate`, as the bytes of an .ogg file. Different `seconds`
## give files of different length, so tests can tell takes apart.
static func silence(seconds: float, rate: int = 8000) -> PackedByteArray:
	var half := 1 << (BLOCK_EXP - 1)
	var packets := maxi(2, floori(seconds * rate / half) + 1)
	var out := PackedByteArray()
	out.append_array(_page([_ident(rate)], 0, 0x02, 0))
	out.append_array(_page([_comment(), _setup()], 1, 0x00, 0))
	var audio: Array[PackedByteArray] = []
	for i in packets:
		audio.append(PackedByteArray([0]))
	out.append_array(_page(audio, 2, 0x04, (packets - 1) * half))
	return out


static func write(path: String, seconds: float) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(silence(seconds))
	f.close()


static func _header(kind: int) -> PackedByteArray:
	var b := PackedByteArray([kind])
	b.append_array("vorbis".to_ascii_buffer())
	return b


static func _ident(rate: int) -> PackedByteArray:
	var b := _header(1)
	var rest := PackedByteArray()
	rest.resize(23)
	rest.encode_u32(0, 0)
	rest.encode_u8(4, 1)
	rest.encode_u32(5, rate)
	rest.encode_s32(9, 0)
	rest.encode_s32(13, 0)
	rest.encode_s32(17, 0)
	rest.encode_u8(21, BLOCK_EXP | (BLOCK_EXP << 4))
	rest.encode_u8(22, 1)
	b.append_array(rest)
	return b


static func _comment() -> PackedByteArray:
	var b := _header(3)
	var vendor := "test".to_ascii_buffer()
	var rest := PackedByteArray()
	rest.resize(4)
	rest.encode_u32(0, vendor.size())
	rest.append_array(vendor)
	var tail := PackedByteArray()
	tail.resize(5)
	tail.encode_u32(0, 0)
	tail.encode_u8(4, 1)
	rest.append_array(tail)
	b.append_array(rest)
	return b


static func _setup() -> PackedByteArray:
	var w := new()
	# One codebook: sync, 1 dimension, 2 entries both 1 bit long, no lookup table.
	w.put(0, 8)
	w.put(0x564342, 24)
	w.put(1, 16)
	w.put(2, 24)
	w.put(0, 1)
	w.put(0, 1)
	w.put(0, 5)
	w.put(0, 5)
	w.put(0, 4)
	# One unused time-domain transform.
	w.put(0, 6)
	w.put(0, 16)
	# One floor of type 1 with no partitions: multiplier 2, 8 range bits.
	w.put(0, 6)
	w.put(1, 16)
	w.put(0, 5)
	w.put(1, 2)
	w.put(8, 4)
	# One residue of type 0 covering nothing, one classification, no cascade books.
	w.put(0, 6)
	w.put(0, 16)
	w.put(0, 24)
	w.put(0, 24)
	w.put(0, 24)
	w.put(0, 6)
	w.put(0, 8)
	w.put(0, 3)
	w.put(0, 1)
	# One mapping: one submap, no coupling, floor 0 and residue 0.
	w.put(0, 6)
	w.put(0, 16)
	w.put(0, 1)
	w.put(0, 1)
	w.put(0, 2)
	w.put(0, 8)
	w.put(0, 8)
	w.put(0, 8)
	# One mode: short blocks, mapping 0.
	w.put(0, 6)
	w.put(0, 1)
	w.put(0, 16)
	w.put(0, 16)
	w.put(0, 8)
	w.put(1, 1)
	var b := _header(5)
	b.append_array(w._bits)
	return b


## Vorbis packs bits least significant first.
func put(value: int, count: int) -> void:
	for i in count:
		if _bit % 8 == 0:
			_bits.append(0)
		if (value >> i) & 1:
			_bits[_bits.size() - 1] |= 1 << (_bit % 8)
		_bit += 1


static func _page(packets: Array, sequence: int, flags: int, granule: int) -> PackedByteArray:
	var lacing := PackedByteArray()
	var body := PackedByteArray()
	for p: PackedByteArray in packets:
		var left := p.size()
		while left >= 255:
			lacing.append(255)
			left -= 255
		lacing.append(left)
		body.append_array(p)
	var head := PackedByteArray()
	head.resize(27)
	head.encode_u32(0, 0x5367674f)
	head.encode_u8(4, 0)
	head.encode_u8(5, flags)
	head.encode_s64(6, granule)
	head.encode_u32(14, SERIAL)
	head.encode_u32(18, sequence)
	head.encode_u32(22, 0)
	head.encode_u8(26, lacing.size())
	head.append_array(lacing)
	head.append_array(body)
	head.encode_u32(22, _crc(head))
	return head


## Ogg's CRC-32: polynomial 0x04c11db7, not reflected, starting at 0.
static func _crc(data: PackedByteArray) -> int:
	var crc := 0
	for byte in data:
		crc ^= byte << 24
		for i in 8:
			crc = ((crc << 1) ^ 0x04c11db7) if crc & 0x80000000 else (crc << 1)
			crc &= 0xffffffff
	return crc
