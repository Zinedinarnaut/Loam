use std::collections::HashMap;

use crate::ir::Program;
use crate::structure::{LaneExit, Structured};

/// A plain back jump with a single conditional predecessor need not kill the lane
/// at its iteration limit. Move the check to that predecessor, using its existing
/// loop exit. The skipped tail's code and the header's incoming values stay intact.
pub(super) fn loop_latch_tails(p: &Program, st: &Structured, rank: &[usize]) -> HashMap<usize, (usize, usize)> {
    let mut tails = HashMap::new();
    for (tail, block) in p.blocks.iter().enumerate() {
        let LaneExit::Jump(header) = st.exits[tail] else { continue };
        let &[branch] = block.preds.as_slice() else { continue };
        if rank[tail] == usize::MAX || rank[header] > rank[tail] || rank[branch] >= rank[tail] {
            continue;
        }
        let LaneExit::Branch { taken, not_taken, .. } = st.exits[branch] else { continue };
        let exit = match (taken == tail, not_taken == tail) {
            (true, false) => not_taken,
            (false, true) => taken,
            _ => continue,
        };
        // The alternate edge must leave the loop altogether, including if its
        // successors reach another latch. In particular it cannot be a second back edge.
        if rank[exit] <= rank[branch] {
            continue;
        }
        let mut seen = vec![false; p.blocks.len()];
        let mut work = vec![exit];
        while let Some(b) = work.pop() {
            if std::mem::replace(&mut seen[b], true) {
                continue;
            }
            if b == header {
                break;
            }
            match st.exits[b] {
                LaneExit::Jump(t) => work.push(t),
                LaneExit::Branch { taken, not_taken, .. } => work.extend([taken, not_taken]),
                LaneExit::End | LaneExit::Indirect => {}
            }
        }
        if !seen[header] {
            tails.insert(branch, (tail, header));
        }
    }
    tails
}
