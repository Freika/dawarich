// Some WebCodecs implementations (notably Firefox on Windows and Linux) emit
// an AVCDecoderConfigurationRecord whose SPS/PPS NAL units start with their NAL
// header byte twice, and whose parameter-set lengths are one byte too large.
// The encoded frames are fine; strict players reject the MP4 because they
// initialize the decoder from this record. Normalize it before mp4-muxer sees
// it. See https://bugzilla.mozilla.org/show_bug.cgi?id=2082867

const AVCC_VERSION = 1
const SPS_NAL_HEADER = 0x67
const PPS_NAL_HEADER = 0x68

function toBytes(description) {
  if (description instanceof ArrayBuffer) return new Uint8Array(description)
  if (ArrayBuffer.isView(description)) {
    return new Uint8Array(
      description.buffer,
      description.byteOffset,
      description.byteLength,
    )
  }
  return null
}

function stripDuplicateHeader(nal) {
  if (
    nal.length > 2 &&
    nal[0] === nal[1] &&
    (nal[0] === SPS_NAL_HEADER || nal[0] === PPS_NAL_HEADER)
  ) {
    return nal.subarray(1)
  }
  return nal
}

function readParameterSets(bytes, offset, count) {
  const sets = []
  let position = offset
  for (let index = 0; index < count; index += 1) {
    if (position + 2 > bytes.length) return null
    const length = (bytes[position] << 8) | bytes[position + 1]
    position += 2
    if (position + length > bytes.length) return null
    sets.push(bytes.subarray(position, position + length))
    position += length
  }
  return { sets, position }
}

function appendBytes(target, bytes) {
  for (const byte of bytes) target.push(byte)
}

/**
 * Return a corrected copy of an AVCDecoderConfigurationRecord, or null when
 * the record is absent, unparseable, or already canonical.
 */
export function sanitizeAvcC(description) {
  const bytes = toBytes(description)
  if (!bytes || bytes.length < 7 || bytes[0] !== AVCC_VERSION) return null

  const numSps = bytes[5] & 0x1f
  const spsResult = readParameterSets(bytes, 6, numSps)
  if (!spsResult || numSps === 0 || spsResult.position >= bytes.length) {
    return null
  }

  const numPps = bytes[spsResult.position]
  const ppsResult = readParameterSets(bytes, spsResult.position + 1, numPps)
  if (!ppsResult || numPps === 0) return null

  const sps = spsResult.sets.map(stripDuplicateHeader)
  const pps = ppsResult.sets.map(stripDuplicateHeader)
  const stripped =
    sps.some((nal, index) => nal.length !== spsResult.sets[index].length) ||
    pps.some((nal, index) => nal.length !== ppsResult.sets[index].length)

  // Bit 0/1 of the length-size byte and bits 0..4 of the SPS-count byte are
  // data; the remaining bits are reserved and must be all ones.
  const lengthSizeByte = 0xfc | (bytes[4] & 0x03)
  const spsCountByte = 0xe0 | numSps
  if (!stripped && bytes[4] === lengthSizeByte && bytes[5] === spsCountByte) {
    return null
  }

  const output = []
  output.push(bytes[0], bytes[1], bytes[2], bytes[3])
  output.push(lengthSizeByte, spsCountByte)
  for (const nal of sps) {
    output.push((nal.length >> 8) & 0xff, nal.length & 0xff)
    appendBytes(output, nal)
  }
  output.push(pps.length)
  for (const nal of pps) {
    output.push((nal.length >> 8) & 0xff, nal.length & 0xff)
    appendBytes(output, nal)
  }
  // Keep the optional High-profile extension bytes (chroma format, bit depths,
  // SPS extensions) verbatim.
  appendBytes(output, bytes.subarray(ppsResult.position))

  return new Uint8Array(output)
}
