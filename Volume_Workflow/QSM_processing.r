################################################################################
# RAYCLOUD QSM TO METRICS (FINAL + CROWN BASE HEIGHT)
# - Obsahuje: Robustní Convex/Concave plochy
# - Obsahuje: Crown Base Height (CBH)
################################################################################

# --- 1. NAČTENÍ KNIHOVEN ---
if (!require("pacman")) install.packages("pacman")
pacman::p_load(dplyr, igraph, concaveman, pracma, alphashape3d, future.apply, progressr, stringr)

# --- 2. NAČÍTACÍ FUNKCE (PARSER) ---
read_raycloud_txt <- function(filepath) {
  raw_lines <- readLines(filepath, warn = FALSE)
  data_lines <- raw_lines[grepl("^[0-9\\.-]", raw_lines)]
  
  full_string <- paste(data_lines, collapse = ",")
  vals <- suppressWarnings(as.numeric(unlist(strsplit(full_string, "[, ]+"))))
  vals <- vals[!is.na(vals)]
  
  if(length(vals) < 6) return(NULL)
  
  len <- floor(length(vals) / 6) * 6
  vals <- vals[1:len]
  
  df <- as.data.frame(matrix(vals, ncol = 6, byrow = TRUE))
  colnames(df) <- c("x", "y", "z", "radius", "parent_id", "section_id")
  
  df$id <- 0:(nrow(df) - 1)
  
  cylinders <- df %>%
    filter(parent_id != -1) %>%
    left_join(df %>% select(id, x, y, z, radius), 
              by = c("parent_id" = "id"), suffix = c(".end", ".start")) %>%
    rename(radius = radius.end)
  
  cylinders$dx <- cylinders$x.end - cylinders$x.start
  cylinders$dy <- cylinders$y.end - cylinders$y.start
  cylinders$dz <- cylinders$z.end - cylinders$z.start
  cylinders$length <- sqrt(cylinders$dx^2 + cylinders$dy^2 + cylinders$dz^2)
  
  cylinders$volume_m3 <- pi * (cylinders$radius^2) * cylinders$length
  cylinders$area_m2 <- 2 * pi * cylinders$radius * cylinders$length
  
  # Detekce kmene
  edges <- cylinders[, c("parent_id", "id")]
  g <- graph_from_data_frame(edges, directed = TRUE)
  root_id <- df$id[df$parent_id == -1]
  top_node_id <- df$id[which.max(df$z)]
  
  if(length(root_id) > 0 && length(top_node_id) > 0) {
    path <- shortest_paths(g, from = as.character(root_id), to = as.character(top_node_id))
    stem_ids <- as.integer(names(path$vpath[[1]]))
    cylinders$BranchOrder <- ifelse(cylinders$id %in% stem_ids, 0, 1)
  } else {
    cylinders$BranchOrder <- 1
  }
  
  cylinders <- cylinders %>% 
    rename(start.x = x.start, start.y = y.start, start.z = z.start,
           end.x = x.end, end.y = y.end, end.z = z.end)
  
  return(list(cylinder = cylinders))
}

# --- 3. VÝPOČETNÍ FUNKCE ---

computeProjections <- function(cylinders) {
  crown <- cylinders[cylinders$BranchOrder >= 1, ]
  if (nrow(crown) < 3) crown <- cylinders 
  if (nrow(crown) < 3) return(rep(0, 6))
  
  pts <- unique(rbind(
    crown[, c("start.x", "start.y", "start.z")],
    setNames(crown[, c("end.x", "end.y", "end.z")], c("start.x", "start.y", "start.z"))
  ))
  
  # Convex (chull)
  calc_convex <- function(mat) {
    tryCatch({
      mat <- unique(mat)
      if(nrow(mat) < 3) return(0)
      h_idx <- chull(mat)
      h_pts <- mat[c(h_idx, h_idx[1]), ]
      abs(polyarea(h_pts[,1], h_pts[,2]))
    }, error = function(e) 0)
  }
  
  # Concave (s fallbackem)
  calc_concave <- function(mat) {
    area <- 0
    try({
      mat <- unique(mat)
      if(nrow(mat) >= 3) {
        hull <- concaveman(mat, concavity = 2) 
        area <- abs(polyarea(hull[,1], hull[,2]))
      }
    }, silent = TRUE)
    
    if(is.na(area) || area < 0.0001) area <- calc_convex(mat)
    return(area)
  }
  
  xz <- pts[, c(1, 3)]; colnames(xz) <- c("x", "z")
  yz <- pts[, c(2, 3)]; colnames(yz) <- c("y", "z")
  xy <- pts[, c(1, 2)]; colnames(xy) <- c("x", "y")
  
  c(
    xz_convex_proj_m2 = calc_convex(xz),
    yz_convex_proj_m2 = calc_convex(yz),
    xy_convex_proj_m2 = calc_convex(xy),
    xz_concave_proj_m2 = calc_concave(xz),
    yz_concave_proj_m2 = calc_concave(yz),
    xy_concave_proj_m2 = calc_concave(xy)
  )
}

computeCentroid <- function(cylinders) {
  crown <- cylinders[cylinders$BranchOrder >= 1, ]
  if (nrow(crown) < 5) crown <- cylinders
  pts <- unique(rbind(crown[, c("start.x", "start.y", "start.z")],
                      setNames(crown[, c("end.x", "end.y", "end.z")], c("start.x", "start.y", "start.z"))))
  tryCatch({
    as <- ashape3d(pts, alpha = 2.0)
    colMeans(as$x)
  }, error = function(e) colMeans(pts))
}

computeStemAngles <- function(stem) {
  if (nrow(stem) == 0) return(c(NA, NA))
  p1 <- c(stem$start.x[1], stem$start.y[1], stem$start.z[1])
  p2 <- c(stem$end.x[nrow(stem)], stem$end.y[nrow(stem)], stem$end.z[nrow(stem)])
  vec <- p2 - p1
  angle_global <- 90 - acos(sum(vec * c(0,0,1)) / sqrt(sum(vec^2))) * 180 / pi
  vecs <- cbind(stem$end.x - stem$start.x, stem$end.y - stem$start.y, stem$end.z - stem$start.z)
  norms <- sqrt(rowSums(vecs^2))
  dots <- vecs[,3] 
  cyl_angles <- 90 - (acos(dots / norms) * 180 / pi)
  return(c(angle_pStart_pEnd = angle_global, mean_cylinder_angle = mean(cyl_angles, na.rm=TRUE)))
}

computeEccentricity <- function(stem, centroid) {
  if (any(is.na(centroid)) || nrow(stem) == 0) return(c(NA, NA, NA, NA))
  p_base <- c(stem$start.x[1], stem$start.y[1], stem$start.z[1])
  p_top <- c(stem$end.x[nrow(stem)], stem$end.y[nrow(stem)], stem$end.z[nrow(stem)])
  v_stem <- p_top - p_base
  v_point <- centroid - p_base
  if(norm(v_stem, type="2") == 0) return(c(NA, NA, NA, NA))
  ecc_axis <- norm(cross(v_stem, v_point), type = "2") / norm(v_stem, type = "2")
  target_z <- centroid[3]
  cyl_idx <- which(stem$start.z <= target_z & stem$end.z >= target_z)
  if (length(cyl_idx) == 0) cyl_idx <- which.min(abs(stem$start.z - target_z))
  else cyl_idx <- cyl_idx[1]
  target_cyl <- stem[cyl_idx, ]
  pc1 <- c(target_cyl$start.x, target_cyl$start.y, target_cyl$start.z)
  pc2 <- c(target_cyl$end.x, target_cyl$end.y, target_cyl$end.z)
  vc_cyl <- pc2 - pc1
  vc_point <- centroid - pc1
  ecc_cyl <- norm(cross(vc_cyl, vc_point), type="2") / norm(vc_cyl, type="2")
  centroid_h_rel <- centroid[3] - stem$start.z[1]
  diam_at_h <- target_cyl$radius * 2
  return(c(centroid_h_rel, ecc_axis, ecc_cyl, diam_at_h))
}

computeTaper <- function(stem) {
  if (nrow(stem) < 2) return("[]")
  min_z <- min(stem$start.z); max_z <- max(stem$end.z)
  z_seq <- seq(min_z + 0.5, max_z, by = 0.5)
  diams <- sapply(z_seq, function(z) {
    idx <- which(stem$start.z <= z & stem$end.z >= z)
    if(length(idx) > 0) return(stem$radius[idx[1]] * 2)
    return(NA)
  })
  return(paste0("[", paste(round(diams, 4), collapse = ", "), "]"))
}

# --- 4. HLAVNÍ FUNKCE ---

processTree <- function(filepath) {
  qsm <- read_raycloud_txt(filepath)
  if(is.null(qsm)) return(NULL)
  cyls <- qsm$cylinder
  
  stem <- cyls[cyls$BranchOrder == 0, ]
  branch <- cyls[cyls$BranchOrder > 0, ]
  
  tree_height_m <- max(cyls$end.z) - min(cyls$start.z)
  base_z <- min(cyls$start.z)
  
  # Crown Base Height
  if(nrow(branch) > 0) {
    cbh_val <- min(branch$start.z) - base_z
    if(cbh_val < 0) cbh_val <- 0 # Pojistka
  } else {
    cbh_val <- NA
  }
  
  dbh_cyl <- stem[stem$start.z <= (base_z + 1.3) & stem$end.z >= (base_z + 1.3), ]
  dbh_qsm_cm <- if(nrow(dbh_cyl) > 0) dbh_cyl$radius[1] * 200 else NA
  
  stem_volume_L <- sum(stem$volume_m3) * 1000
  branch_volume_L <- sum(branch$volume_m3) * 1000
  tree_volume_L <- stem_volume_L + branch_volume_L
  
  stem_area_m2 <- sum(stem$area_m2)
  branch_area_m2 <- sum(branch$area_m2)
  tree_area_m2 <- stem_area_m2 + branch_area_m2
  
  projs <- computeProjections(cyls)
  angles <- computeStemAngles(stem)
  centroid <- computeCentroid(cyls)
  ecc_stats <- computeEccentricity(stem, centroid)
  taper_str <- computeTaper(stem)
  
  res <- data.frame(
    dbh_qsm_cm = dbh_qsm_cm, 
    tree_height_m = tree_height_m,
    Crown_Base_Height = cbh_val, # NOVÝ SLOUPEC
    stem_volume_L = stem_volume_L, 
    branch_volume_L = branch_volume_L, 
    tree_volume_L = tree_volume_L,
    stem_area_m2 = stem_area_m2, 
    branch_area_m2 = branch_area_m2, 
    tree_area_m2 = tree_area_m2,
    
    xz_convex_proj_m2 = projs["xz_convex_proj_m2"], 
    yz_convex_proj_m2 = projs["yz_convex_proj_m2"], 
    xy_convex_proj_m2 = projs["xy_convex_proj_m2"],
    xz_concave_proj_m2 = projs["xz_concave_proj_m2"], 
    yz_concave_proj_m2 = projs["yz_concave_proj_m2"], 
    xy_concave_proj_m2 = projs["xy_concave_proj_m2"],
    
    angle_pStart_pEnd = angles[1], 
    mean_cylinder_angle = angles[2],
    
    centroid_height = ecc_stats[1], 
    ecc2stem_axis = ecc_stats[2], 
    ecc2cylinder = ecc_stats[3],
    diamAt_centroidH = ecc_stats[4], 
    diamAt_centroidH_raw = ecc_stats[4],
    
    stemTaper = taper_str, 
    stemTaper_raw = taper_str,
    
    file = basename(filepath), 
    stringsAsFactors = FALSE
  )
  return(res)
}

# --- SPUŠTĚNÍ ---
plan(multisession, workers = 4)
files <- list.files(pattern = "\\.txt$", full.names = TRUE)

if(length(files) > 0) {
  message(paste("Zpracovávám", length(files), "souborů..."))
  with_progress({
    p <- progressor(along = files)
    results <- future_lapply(files, function(f) {
      p(basename(f))
      tryCatch(processTree(f), error = function(e) { message(paste("Error:", basename(f), e)); NULL })
    }, future.seed = TRUE)
  })
  
  final_df <- do.call(rbind, results)
  if(!is.null(final_df)) {
    write.csv(final_df, "Raycloud_Metrics_Final_CBH.csv", row.names = FALSE)
    print(head(final_df[, c("file", "tree_height_m", "Crown_Base_Height")]))
    message("Hotovo! Uloženo jako Raycloud_Metrics_Final_CBH.csv")
  }
}