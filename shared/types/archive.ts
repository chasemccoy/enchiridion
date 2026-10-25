/** One capture in a record's archive folder: the current copy or a past version, as amber filed it. */
export interface ArchiveVersion {
  /** Folder relative to the archive root, served under /archives/. */
  path: string;
  /** When the page looked like this: the Wayback snapshot's date, else when it was captured. */
  date: string | null;
  /** From the Wayback Machine rather than the live site. */
  wayback: boolean;
  title: string | null;
  /** The folder's top copy, the one the record shows by default. */
  current: boolean;
}
