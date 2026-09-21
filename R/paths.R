# where the run artifacts live. the repo holds configuration only, so every
# example config builds its paths from one root supplied by the environment
# rather than committing an absolute path that is valid on one machine.

##' @title Root directory for calibration run artifacts
##' @name data_root
##' @author Akash BV
##'
##' @description Returns the directory holding run workspaces, prepared inputs
##' and result caches, read from the `CALIBRATION_DATA_ROOT` environment
##' variable. Example configs call this so no absolute path is committed.
##' Fails rather than returning an empty string, because an unset root would
##' otherwise silently produce paths rooted at `/` that fail much later with a
##' confusing message.
##'
##' @param ... path components appended to the root, as in [file.path()].
##' @return character path.
##' @examples
##' \dontrun{
##' Sys.setenv(CALIBRATION_DATA_ROOT = "/path/to/artifacts")
##' data_root("cal_val_joint", "cache")
##' }
##' @export
data_root <- function(...) {
  root <- Sys.getenv("CALIBRATION_DATA_ROOT")
  if (!nzchar(root)) {
    PEcAn.logger::logger.severe(
      "CALIBRATION_DATA_ROOT is not set. Point it at the directory holding ",
      "the run workspaces, prepared inputs and caches, for example ",
      "export CALIBRATION_DATA_ROOT=/path/to/artifacts"
    )
  }
  file.path(root, ...)
}
