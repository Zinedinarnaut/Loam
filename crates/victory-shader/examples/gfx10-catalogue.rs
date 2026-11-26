//! Enumerates the instruction encodings that Loam's decoder can name.
//! The words below are synthetic and contain no title data.

use std::io::{self, Write};
use std::ops::Range;

use victory_shader::gfx10::{Encoding, decode};

type Family = (&'static str, Encoding, Range<u16>);

const ALU: &[Family] = &[
    ("SOP2", Encoding::Sop2, 0..0x60),
    ("SOPK", Encoding::Sopk, 0..0x1d),
    ("SOP1", Encoding::Sop1, 0..0x100),
    ("SOPC", Encoding::Sopc, 0..0x80),
    ("SOPP", Encoding::Sopp, 0..0x80),
    ("VOP2", Encoding::Vop2, 0..0x3e),
    ("VOP1", Encoding::Vop1, 0..0x100),
    ("VOPC", Encoding::Vopc, 0..0x100),
    ("VOPC in VOP3", Encoding::Vop3, 0..0x100),
    ("VOP2 in VOP3", Encoding::Vop3, 0x100..0x140),
    ("VOP3", Encoding::Vop3, 0x140..0x180),
    ("VOP1 in VOP3", Encoding::Vop3, 0x180..0x200),
    ("VOP3", Encoding::Vop3, 0x200..0x400),
    ("VOP3P", Encoding::Vop3p, 0..0x80),
    ("VINTRP", Encoding::Vintrp, 0..4),
];

const MEMORY_AND_EXPORT: &[Family] = &[
    ("SMEM", Encoding::Smem, 0..0x100),
    ("DS", Encoding::Ds, 0..0x100),
    ("MUBUF", Encoding::Mubuf, 0..0x100),
    ("MTBUF", Encoding::Mtbuf, 0..0x10),
    ("MIMG", Encoding::Mimg, 0..0x100),
    ("FLAT", Encoding::Flat, 0..0x80),
    ("GLOBAL", Encoding::Global, 0..0x80),
    ("SCRATCH", Encoding::Scratch, 0..0x80),
    ("EXP", Encoding::Exp, 0..1),
];

fn words(encoding: Encoding, op: u16) -> [u32; 4] {
    let op = u32::from(op);
    let (w0, w1) = match encoding {
        Encoding::Sop2 => (0x8000_0000 | op << 23, 0),
        Encoding::Sopk => (0xb000_0000 | op << 23, 0),
        Encoding::Sop1 => (0xbe80_0000 | op << 8, 0),
        Encoding::Sopc => (0xbf00_0000 | op << 16, 0),
        Encoding::Sopp => (0xbf80_0000 | op << 16, 0),
        Encoding::Smem => (0xf400_0000 | op << 18, 0),
        Encoding::Vop2 => (op << 25, 0),
        Encoding::Vop1 => (0x7e00_0000 | op << 9, 0),
        Encoding::Vopc => (0x7c00_0000 | op << 17, 0),
        Encoding::Vop3 => (0xd400_0000 | op << 16, 0),
        Encoding::Vop3p => (0xcc00_0000 | op << 16, 0),
        Encoding::Vintrp => (0xc800_0000 | op << 16, 0),
        Encoding::Ds => (0xd800_0000 | op << 18, 0),
        Encoding::Mubuf => (0xe000_0000 | (op & 0x7f) << 18 | (op >> 7) << 25, 0),
        Encoding::Mtbuf => (0xe800_0000 | (op & 7) << 16, (op >> 3) << 21),
        Encoding::Mimg => (0xf000_0000 | (op & 0x7f) << 18 | (op >> 7), 0),
        Encoding::Flat => (0xdc00_0000 | op << 18, 0),
        Encoding::Global => (0xdc00_8000 | op << 18, 0),
        Encoding::Scratch => (0xdc00_4000 | op << 18, 0),
        Encoding::Exp => (0xf800_0000, 0),
    };
    // One word of padding for inline literals, followed by branch targets
    // that end the program regardless of the probed instruction's length.
    [w0, w1, 0xbf81_0000, 0xbf81_0000]
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut out = io::BufWriter::new(io::stdout().lock());
    for (panel, families) in [("alu", ALU), ("memory", MEMORY_AND_EXPORT)] {
        for (family, encoding, opcodes) in families {
            for opcode in opcodes.clone() {
                let code = words(*encoding, opcode);
                let bytes: Vec<_> = code.into_iter().flat_map(u32::to_le_bytes).collect();
                let instructions = decode(&bytes)?;
                let first = &instructions[0];
                assert_eq!((first.encoding, first.opcode), (*encoding, opcode));
                let name = first.name().unwrap_or("-");
                writeln!(out, "{panel}\t{family}\t{opcode:#05x}\t{name}")?;
            }
        }
    }
    out.flush()?;
    Ok(())
}
