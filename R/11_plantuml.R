plantuml_skinparam <- "
skinparam ActivityBorderColor black
skinparam ActivityBackgroundColor #ededed
skinparam SequenceGroupBorderColor black
skinparam ActivityDiamondBorderColor black
skinparam ArrowColor black
"
flow_view_plantuml <- function(x_chr, x, prefix, sub_fun_id, swap, out, svg) {

  if(is.function(x) && is.null(body(x)))
    stop("`", x_chr,
         "` doesn't have a body (try `body(", x_chr,
         ")`). {flow}'s functions don't work on such inputs.")

  # relevant only for functions
  # put comments in `#`() calls so we can manipulate them as code,
  # the function `build_blocks()`, called itself in `add_data_from_expr()`,
  # will deal with them further down the line
  x <- add_comment_calls(x, prefix)

  # deal with sub functions (function definitions found in the code)
  sub_funs <- find_funs(x)
  if (!is.null(sub_fun_id)) {
    # if we gave a sub_fun_id, make this subfunction our new x
    x_chr <- "fun"
    x <- eval(sub_funs[[sub_fun_id]])
  } else {
    if (length(sub_funs)) {
      # else print them for so user can choose a sub_fun_id if relevant
      message("We found function definitions in this code, ",
              "use the argument sub_fun_id to inspect them")
      print(sub_funs)
    }
  }

  # header and start node
  if(is.function(x)) {
    header <- deparse_plantuml(args(x))
    # remove the {}
    #header <- paste(header[-length(header)], collapse = "\\n")
    header <- substr(header, 1, nchar(header) - 11)
    # replace the function(arg) by my_function(arg)
    header <- sub("^function", x_chr, header)
    # make it a proper plantuml title
    header <- paste0("title ", header, "\nstart\n")
  } else {
    header <- "start\n"
  }

  # main code
  body_ <- body(x)
  if (swap) body_ <- swap_calls(body_)
  code_str <- build_plantuml_code(body_, first = TRUE)
  # concat params, header and code
  code_str <- paste0(plantuml_skinparam,"\n", header, code_str)

  gfn <- getFromNamespace
  plantuml <- gfn("plantuml", "plantuml")
  plant_uml_object <- plantuml(code_str)

  if(is.null(out)) {
    plot(plant_uml_object, vector = svg)
    return(NULL)
  }

  is_tmp <- out %in% c("html", "htm", "png", "pdf", "jpg", "jpeg")
  if (is_tmp) {
    out <- tempfile("flow_", fileext = paste0(".", out))
  }
  plot(plant_uml_object, vector = svg, file = out)

  if (is_tmp) {
    message(sprintf("The diagram was saved to '%s'", gsub("\\\\","/", out)))
    browseURL(out)
  }
  NULL
}

build_plantuml_code <- function(expr, first = FALSE) {
  if(is.call(expr) && identical(expr[[1]], quote(`{`))) {
    calls <- as.list(expr)[-1]
  } else {
    calls <- list(expr)
  }

  # support empty calls (`{}`)
  if (!length(calls)) {
    blocks <- list(substitute()) # substitute() returns an empty call
    return(blocks)
  }
  # logical indices of control flow calls
  cfc_lgl <- calls %call_in% c("if", "for", "while", "repeat")

  # logical indices of comment calls `#`()
  special_comment_lgl <- calls %call_in% c("#")

  # there are 2 ways to start a block : be a cf not preceded by com, or be a com
  # there are 2 ways to finish a block : be a cf (and finish on next one), or start another block and finish right there

  # cf not preceded by com
  cfc_unpreceded_lgl <- cfc_lgl & !c(FALSE, head(special_comment_lgl, -1))
  # new_block (first or after cfc)
  new_block_lgl <- c(TRUE, head(cfc_lgl, -1))
  block_ids <- cumsum(special_comment_lgl | cfc_unpreceded_lgl | new_block_lgl)

  blocks <- split(calls, block_ids)

  n_blocks <- length(blocks)
  if(first && length(blocks[[n_blocks]]) > 1) {
    #browser()
    # at first iteration we separate the last call so it can be used as a return call
    l_last_block <- length(blocks[[n_blocks]])
    blocks[[n_blocks+1]] <- blocks[[n_blocks]][l_last_block]
    blocks[[n_blocks]] <- blocks[[n_blocks]][-l_last_block]
    n_blocks <- n_blocks + 1
  }

  res <- sapply(blocks, function(expr) {
    #### starts with SYMBOL / LITTERAL
    if(!is.call(expr[[1]]) || length(expr) > 1) {
      deparsed <- sapply(expr, deparse_plantuml)
      return(paste0(":", paste(deparsed, collapse = "\\n"), ";"))
    }

    expr <- expr[[1]]

    #### IF
    if(identical(expr[[1]], quote(`if`))) {
      if_txt   <- sprintf(
        "#e2efda:if (if(%s)) then (y)",
        deparse_plantuml(expr[[2]]))
      yes_txt <- build_plantuml_code(expr[[3]])
      if (length(expr) == 4) {
        elseif_txt <- build_elseif_txt(expr[[4]])
        txt <- paste(if_txt, yes_txt, elseif_txt, "endif", sep = "\n")
      } else {
        txt <- paste(if_txt, yes_txt, "endif", sep = "\n")
      }
      return(txt)
    }

    #### WHILE
    if(identical(expr[[1]], quote(`while`))) {
      while_txt   <- sprintf(
        "#fff2cc:while (while(%s))",
        deparse_plantuml(expr[[2]]))
      expr_txt <- build_plantuml_code(expr[[3]])
      txt <- paste(while_txt, expr_txt, "endwhile", sep = "\n")
      return(txt)
    }

    #### FOR
    if(identical(expr[[1]], quote(`for`))) {
      for_txt   <- sprintf(
        "#ddebf7:while (for(%s in %s))",
        deparse_plantuml(expr[[2]]),
        deparse_plantuml(expr[[3]]))
      expr_txt <- build_plantuml_code(expr[[4]])
      txt <- paste(for_txt, expr_txt, "endwhile", sep = "\n")
      return(txt)
    }

    #### REPEAT
    if(identical(expr[[1]], quote(`for`))) {
      repeat_txt   <- "#fce4d6:while (repeat)"
      expr_txt <- build_plantuml_code(expr[[2]])
      txt <- paste(repeat_txt, expr_txt, "endwhile", sep = "\n")
      return(txt)
    }

    #### STOP
    if(identical(expr[[1]], quote(`stop`))) {
      stop_txt <- deparse_plantuml(expr)
      return(paste0("#ed7d31:",stop_txt, ";\nstop"))
    }

    #### RETURN
    if(identical(expr[[1]], quote(`return`))) {
      return_txt   <- deparse_plantuml(expr)
      return(paste0("#70ad47:",return_txt, ";\nstop"))
    }

    #### REGULAR CALL
    paste0(":", deparse_plantuml(expr), ";")
  })

  if(first) {
    if(startsWith(res[n_blocks], ":"))
      res[n_blocks] <- paste0("#70ad47", res[n_blocks])
    else if(startsWith(res[n_blocks], "#e2efda:if"))
      res[n_blocks] <- sub("^#e2efda", "#70ad47", res[n_blocks])
    if(res[n_blocks] != "stop")
      res[n_blocks] <- paste0(res[n_blocks], "\nstop")
  }

  paste(res, collapse="\n")
}

build_elseif_txt <- function(expr) {
  is_elseif <-
    is.call(expr) && identical(expr[[1]], quote(`if`))
  if(is_elseif) {
    elseif_txt <- sprintf(
      "#e2efda:elseif (if(%s)) then (y)",
      paste(deparse_plantuml(expr[[2]]), collapse= "\\n"))
    yes_txt <- build_plantuml_code(expr[[3]])
    if(length(expr) == 4)
      txt <- paste(elseif_txt, yes_txt, build_elseif_txt(expr[[4]]), sep = "\n")
    else {
      txt <- paste(elseif_txt, yes_txt, sep = "\n")
    }
  } else {
      else_txt <- "else (n)"
      no_txt <-  build_plantuml_code(expr)
      txt <- paste(else_txt, no_txt, sep = "\n")
  }
  txt
}

# deparse an expression to a correctly escaped character vector
deparse_plantuml <- function(x) {
  x <- paste(deparse(x, backtick = TRUE),collapse = "\n")
  x <- styler::style_text(x)
  chars <- c("\\[","\\]","~","\\.","\\*","_","\\-",'"', "<", ">", "&", "\\\\")
  x <- to_unicode(x, chars) #
  x <- paste(x, collapse = "\\n")
  x
}

to_unicode <- function(x, chars = character()) {
  if(length(chars)) {
    # if chars is given, replace recursively the matches
    m <- gregexpr(paste(chars, collapse="|"), x)
    regmatches(x, m) <- lapply(regmatches(x, m), to_unicode)
    return(x)
  }
  # encode all to UTF-8
  x <- ifelse(Encoding(x) != 'UTF-8', enc2utf8(enc2native(x)), x)
  bytes <- iconv(x, "UTF-8", "UTF-32BE", toRaw=TRUE)
  vapply(bytes, FUN.VALUE = character(1), function(x) paste(sprintf(
    "<U+%s%s>", x[c(FALSE, FALSE, TRUE, FALSE)], x[c(FALSE, FALSE, FALSE, TRUE)]),
    collapse = ""))
}

# view_pant_ulm(median.default)
