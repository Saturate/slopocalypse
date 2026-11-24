# 0021. Rust work off the main thread runs on its own threads

Status: accepted
Date: 2026-11-24
Issue or PR: #391

## Context
Meshing one voxel ground tile in Rust (`VoxelGround.tile_arrays`) took up to 14 ms, all of it
on the main thread, so driving into new ground stalled frames. Sampling the ground already ran
on Godot's `WorkerThreadPool`, but gdext 0.5 refuses a call into an extension class from any
thread but the main one ("Attempted to access binding from different thread than main
thread; this is UB"), so the meshing could not simply move into that task.

## Decision
A Rust binding that needs work done off the main thread runs it on threads of its own. The
main thread copies the inputs out of Godot's types into plain Rust data, queues them and gets
a job id (`VoxelGround.mesh_start`); a few threads started by the extension do the work
without touching any Godot API; the main thread polls (`mesh_ready`), takes the result as
Godot arrays (`mesh_take`) or throws it away (`mesh_drop`). Scripts never block on a job:
they poll and step their own work under a per-frame budget.

## Alternatives
- gdext's `experimental-threads` feature, which lets Godot's worker threads call into the
  extension. It changes how every class in every extension is bound and is marked
  experimental; not worth it for one hot path.
- Keeping the meshing on the main thread and doing fewer tiles a frame: one fine tile alone
  overran the frame.
- Building the `ArrayMesh` on a worker too: the rendering server's thread rules for that are
  less clear, and the upload measured about 0.1 ms a tile, so it stays on the main thread.

## Consequences
The pure crate stays as it is; only the binding knows about threads. Each such binding owns a
small pool and an id table, and every id must end in a take or a drop. If gdext makes
worker-thread calls safe by default, this can move onto `WorkerThreadPool` like the rest.
