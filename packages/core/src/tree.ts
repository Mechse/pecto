/** Workspace tree shapes, shared between the server's /api/tree and the web UI. */

export interface TreeTask {
  /** File name, which is also the path relative to the workspace root. */
  path: string;
  name?: string;
  description?: string;
  /** `{{variable}}` names found in the instructions — the task's inputs. */
  placeholders?: string[];
  error?: string;
}
