#' @title List the targets that are out of date.
#' @description Outdated targets will be rebuilt in the next
#'   [make()].
#' @details `outdated()` is sensitive to the alternative triggers
#' described at
#' <https://ropenscilabs.github.io/drake-manual/debug.html>.
#' For example, even if `outdated(...)` shows everything up to date,
#' `outdated(..., trigger = "always")` will show
#' all targets out of date.
#' You must use a fresh `config` argument with an up-to-date
#' `config$targets` element that was never modified by hand.
#' If needed, rerun [drake_config()] early and often.
#' See the details in the help file for [drake_config()].
#' @export
#' @seealso [drake_config()], [missed()], [drake_plan()],
#'   [make()]
#' @return Character vector of the names of outdated targets.
#' @param config Optional internal runtime parameter list
#'   produced with [drake_config()].
#'   You must use a fresh `config` argument with an up-to-date
#'   `config$targets` element that was never modified by hand.
#'   If needed, rerun [drake_config()] early and often.
#'   See the details in the help file for [drake_config()].
#' @param make_imports Logical, whether to make the imports first.
#'   Set to `FALSE` to save some time and risk obsolete output.
#' @param do_prework Whether to do the `prework`
#'   normally supplied to [make()].
#' @examples
#' \dontrun{
#' test_with_dir("Quarantine side effects.", {
#' if (suppressWarnings(require("knitr"))) {
#' load_mtcars_example() # Get the code with drake_example("mtcars").
#' # Recopute the config list early and often to have the
#' # most current information. Do not modify the config list by hand.
#' config <- drake_config(my_plan)
#' outdated(config = config) # Which targets are out of date?
#' make(my_plan) # Run the projects, build the targets.
#' config <- drake_config(my_plan)
#' # Now, everything should be up to date (no targets listed).
#' outdated(config = config)
#' # outdated() is sensitive to triggers.
#' # See the debugging guide: https://ropenscilabs.github.io/drake-manual/debug.html # nolint
#' config$trigger <- "always"
#' outdated(config = config)
#' }
#' })
#' }
outdated <-  function(
  config,
  make_imports = TRUE,
  do_prework = TRUE
) {
  assert_config_not_plan(config)
  if (do_prework) {
    do_prework(config = config, verbose_packages = config$verbose)
  }
  if (make_imports) {
    process_imports(config = config)
  }
  from <- first_outdated(config = config)
  log_msg("find downstream outdated targets", config = config)
  to <- downstream_nodes(config$schedule, from)
  sort(unique(as.character(c(from, to))))
}

first_outdated <- function(config) {
  config$ht_get_hash <- ht_new() # Memoize getting hashes from the cache.
  on.exit(ht_clear(config$ht_get_hash)) # Needs to be empty afterwards.
  schedule <- config$schedule
  out <- character(0)
  old_leaves <- NULL
  while (TRUE) {
    log_msg("find more outdated targets", config = config)
    new_leaves <- setdiff(leaf_nodes(schedule), out)
    do_build <- lightly_parallelize(
      X = new_leaves,
      FUN = function(target) {
        if (!target_exists(target, config)) {
          return(TRUE)
        }
        meta <- drake_meta_(target, config)
        should_build_target(target, meta, config)
      },
      jobs = config$jobs_preprocess
    )
    do_build <- unlist(do_build)
    out <- c(out, new_leaves[do_build])
    if (all(do_build)) {
      break
    } else {
      schedule <- delete_vertices(schedule, v = new_leaves[!do_build])
    }
    old_leaves <- new_leaves
  }
  out
}

#' @title Report any import objects required by your drake_plan
#'   plan but missing from your workspace or file system.
#' @description Checks your workspace/environment and
#' file system.
#' @export
#' @seealso [outdated()]
#' @return Character vector of names of missing objects and files.
#'
#' @param config Internal runtime parameter list
#'   produced by both [drake_config()] and [make()].
#'
#' @examples
#' \dontrun{
#' test_with_dir("Quarantine side effects.", {
#' if (suppressWarnings(require("knitr"))) {
#' load_mtcars_example() # Get the code with drake_example("mtcars").
#' config <- drake_config(my_plan)
#' missed(config) # All the imported files and objects should be present.
#' rm(reg1) # Remove an import dependency from you workspace.
#' missed(config) # Should report that reg1 is missing.
#' }
#' })
#' }
missed <- function(config) {
  assert_config_not_plan(config)
  imports <- igraph::V(config$imports)$name
  is_missing <- lightly_parallelize(
    X = imports,
    FUN = function(x) {
      missing_import(x, config = config)
    },
    jobs = config$jobs
  )
  is_missing <- as.logical(is_missing)
  if (!any(is_missing)) {
    return(character(0))
  }
  display_keys(imports[is_missing])
}
