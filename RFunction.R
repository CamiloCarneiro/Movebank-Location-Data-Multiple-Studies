library('move2')
library('keyring')
library('lubridate')
library("dplyr")
library("sf")
library("xml2")
library("purrr")
library("vctrs")
library("rlang")
library("moveapps")



rFunction = function(data=NULL,
                     username,
                     password,
                     select_sensors,
                     incl_outliers=FALSE,
                     minarg=FALSE,
                     thin=FALSE,
                     thin_numb=6,
                     thin_unit="hours",
                     timestamp_start=NULL,
                     timestamp_end=NULL,
                     lastXdays=NULL,
                     study_access = "both",
                     ...) {
  
  options("keyring_backend"="env")
  
  time0 <- Sys.time()
  
  
  # retry loop: attempts Movebank access for up to 30 minutes
  while(Sys.time() < (time0+1800) & !exists("locs", inherits = FALSE))
  {
    # sleep logic: backoff delays depending on elapsed time
    if (Sys.time()>time0+2 & Sys.time()<=time0+600) Sys.sleep(60) # after 2 seconds only try every 1 minute
    if (Sys.time()>time0+600) Sys.sleep(300) # after 10 minutes only try every 5 minutes
    logger.info(paste("Try Movebank access at:", Sys.time()))
    try( 
      expr = {
        # store Movebank login credentials
        movebank_store_credentials(username,password)
        
        # ---- Select studies by user access type
          logger.info(paste("Selecting studies based on access type:", study_access))
          
          # fetch all studies and permissions
          studies <- movebank_retrieve("study")
          
          # subset studies according to access permission
          if (study_access == "collaborator") {
            allowed <- studies[studies$study_permission == "collaborator", ]
          } else if (study_access == "data_manager") {
            allowed <- studies[studies$study_permission == "data_manager", ]
          } else if (study_access == "both") {
            allowed <- studies[
              studies$study_permission == "collaborator" |
                studies$study_permission == "data_manager",
            ]
          } else if (study_access == "download") {
            allowed <- studies[
              studies$i_have_download_access == TRUE,
            ]
          }
          
          # if no studies match, exit early
          if (nrow(allowed) == 0) {
            logger.info("No studies found for selected access type → returning NULL.")
            result <- NULL
            next
          }
          
          # list of study IDs to download
          study_list <- allowed$id
          
          logger.info(paste(
            "User has access to", nrow(allowed), "studies:",
            paste(study_list, collapse = ", ")
          ))
          
          # initialize argument list for Movebank API calls
        arguments <- list()   
        
        
        # ---- Sensor selection
        if (is.null(select_sensors))
        {
          logger.info("No sensors specified; all location sensors downloaded.")
          all_locations_sensors <-  movebank_retrieve(entity_type="tag_type") %>%
            filter(is_location_sensor == TRUE) %>% pull(id)
          
          arguments[["sensor_type_id"]] <- all_locations_sensors
          
        } else {
          # convert comma-separated string into numeric vector
          if (is.character(select_sensors)) {
            select_sensors_vec <- as.integer(unlist(strsplit(select_sensors, ",")))
          arguments[["sensor_type_id"]] <- select_sensors_vec
          }
          
          
          
          
          # retrieve sensor metadata and log selected sensor names
          sensorInfo <- movebank_retrieve(entity_type = "tag_type")
          select_sensors_name <- sensorInfo$name[which(as.numeric(sensorInfo$id) %in% arguments[["sensor_type_id"]])]
          logger.info(paste(
            "You have selected to download locations of these selected sensor types:",
            paste(select_sensors_name, collapse = ", ")
          ))
          
          # ---- Include or exclude Movebank-marked outliers
          if (incl_outliers==TRUE) 
          {
            logger.info ("Also locations marked as outliers in Movebank (visible=FALSE) will be downloaded. Note that this may lead to unexpected results.")
          } else 
          {
            arguments[["remove_movebank_outliers"]] <- TRUE
            logger.info ("Only data that were not marked as outliers previously are downloaded (default).")
          }
          
          # ---- Minimal attribute selection
          if (minarg==TRUE) 
          {
            arguments[["attributes"]] <- c("tag_local_identifier","individual_local_identifier","deployment_id","sensor_type_id", "study_id")
            logger.info("You have selected to only include the minimum set of event attributes: timestamp, track_id and the location. The track attributes will be fully included.")
          }
          
          # ---- Timestamp filters
          if (!is.null(timestamp_start)) {
            logger.info(paste0("timestamp_start is set and will be used: ", timestamp_start))
            arguments["timestamp_start"] = timestamp_start
          } else {
            logger.info("timestamp_start not set.")
          }
          
          if (!is.null(timestamp_end)) {
            logger.info(paste0("timestamp_end is set and will be used: ", timestamp_end))
            arguments["timestamp_end"] = timestamp_end
          } else {
            logger.info("timestamp_end not set.")
          }
          
          # Last days filder (override timestamps if lastXdays is provided)
          if(!is.null(lastXdays)){
            timestamp_start <- now(tzone="UTC") - days(lastXdays)
            arguments[["timestamp_start"]]  <-  timestamp_start ## why sometimes there are 2 square brackets and sometimes just one?
            arguments["timestamp_end"]  <-  NULL
            logger.info(paste0("data will be downloaded starting from: ", timestamp_start, " this is ",lastXdays, " before now. If timestamp_start or timestamp_end are set, these values will be ignored"))
          }
          
          
          # ---- Download loop for each study 
          locs_list <- list()
          
          for (s_id in study_list) {
            class(s_id)<-"integer64"
            arguments[["study_id"]] <- s_id
            logger.info(paste("Downloading Movebank study:", s_id))
            
            # download study data; errors return NULL
            tmp <- tryCatch(do.call(movebank_download_study, arguments), error = function(e) NULL)
            if (is.null(tmp)) next
            if (NROW(tmp) == 0) {
              message(sprintf("Study %s returned 0 rows.", arguments$study_id))
              next
            }
        
            locs_list[[as.character(s_id)]] <- tmp
            # light delay between requests
            Sys.sleep(0.3)
          }
          
 
          # add study_id column to each dataset
          locs_list2 <- Map(function(df, nm) {
            df$study_id <- nm
            df
          }, locs_list, names(locs_list))
          
          # stack all studies into a single move2 object
          locs <- do.call(mt_stack, c(unname(locs_list2), list(.track_combine = "rename")))          
          
      
          
          # ---- Quality checks / cleaning steps
          
          # ensure track IDs are properly grouped
          if(!mt_is_track_id_cleaved(locs))
          {
            logger.info("Your data set was not grouped by individual/track. We regroup it for you.")
            locs <- locs |> dplyr::arrange(mt_track_id(locs))
          }
          
          # ensure time ordering within tracks
          if (!mt_is_time_ordered(locs))
          {
            logger.info("Your data is not time ordered (within the individual/track groups). We reorder the locations for you.")
            locs <- locs |> dplyr::arrange(mt_track_id(locs),mt_time(locs))
          }
          
          # remove empty geometries
          if(!mt_has_no_empty_points(locs))
          {
            logger.info("Your data included empty points. We remove them for you.")
            locs <- dplyr::filter(locs, !sf::st_is_empty(locs))
          }
          
          # remove records where lat/long individually NA
          crds <- sf::st_coordinates(locs)
          rem <- unique(c(which(is.na(crds[,1])),which(is.na(crds[,2]))))
          if(length(rem)>0){
            locs <- locs[-rem,]
          }
          
          

          # remove duplicates by selecting rows with fewer NAs
          if (!mt_has_unique_location_time_records(locs))
          {
            n_dupl <- length(which(duplicated(paste(mt_track_id(locs),mt_time(locs)))))
            logger.info(paste("Your data has",n_dupl, "duplicated location-time records. We removed here those with less info and then select the first if still duplicated."))
            ## this piece of code keeps the duplicated entry with least number of columns with NA values
            locs <- locs %>%
              mutate(n_na = rowSums(is.na(pick(everything())))) %>%
              arrange(n_na) %>%
              mt_filter_unique(criterion='first') %>% # this always needs to be "first" because the duplicates get ordered according to the number of columns with NA. 
              dplyr::arrange(mt_track_id()) %>%
              dplyr::arrange(mt_track_id(),mt_time())
          }
          
          # ---- Thinning: select first location in time intervals
          if (thin==TRUE) 
          {
            logger.info(paste("Your data will be thinned as requested to one location per",thin_numb,thin_unit))
            #order as suggested by error message (done by dplyr before, did not work???)
            locs <- locs[order(mt_track_id(locs),mt_time(locs)),]
            locs <- mt_filter_per_interval(locs,criterion="first",unit=paste(thin_numb,thin_unit))
            locs <- locs %>% group_by(mt_track_id()) %>% slice(if(n()>1) -1 else 1) %>% ungroup ## the thinning happens within the time window, so the 1st location is mostly off. After the 1st location the intervals are regular if the data allow for it. If track endsup only with one location, this one is retained
            locs <-  locs %>% select (-c(`mt_track_id()`)) # this column gets added when using group_by()
          } 
          
          # ensure track IDs are valid R names
          mt_track_id(locs) <- make.names(mt_track_id(locs),allow_=TRUE)
          
          # ---- Combine with input data (if provided) ----
          if (!is.null(data)){
            if (!st_crs(data)==st_crs(locs)){
              locs <- st_transform(locs, st_crs(data))
              logger.info(paste0("The new data sets to combine has a different projection. It has been re-projected, and now the combined data set is in the '",st_crs(data)$input,"' projection."))
            }
            result <- mt_stack(data,locs,.track_combine="rename") ## mt_stack(...,track_combine="rename") #check if only renamed at duplication; read about and test track_id_repair
            
            # flatten list-type track data columns
            if(any(sapply(mt_track_data(result), is_bare_list))){
              result <- result |> mutate_track_data(across(
                where( ~is_bare_list(.x) && all(purrr::map_lgl(.x, function(y) 1==length(unique(y)) ))), 
                ~do.call(vctrs::vec_c,purrr::map(.x, head,1))))
              if(any(sapply(mt_track_data(result), is_bare_list))){
                result <- result |> mutate_track_data(across(
                  where( ~is_bare_list(.x) && any(purrr::map_lgl(.x, function(y) 1!=length(unique(y)) ))), 
                  ~unlist(purrr::map(.x, paste, collapse=","))))
              }
            }
          }else{
            
            # if no input data, return only downloaded data
            result <- locs
            
            # flatten list-type columns similarly
            if(any(sapply(mt_track_data(result), is_bare_list))){
              result <- result |> mutate_track_data(across(
                where( ~is_bare_list(.x) && all(purrr::map_lgl(.x, function(y) 1==length(unique(y)) ))), 
                ~do.call(vctrs::vec_c,purrr::map(.x, head,1))))
              if(any(sapply(mt_track_data(result), is_bare_list))){
                result <- result |> mutate_track_data(across(
                  where( ~is_bare_list(.x) && any(purrr::map_lgl(.x, function(y) 1!=length(unique(y)) ))), 
                  ~unlist(purrr::map(.x, paste, collapse=","))))
              }
            }
          }
        }
      },silent=TRUE)
  }
  
  if(!exists("result"))
  {
    result <- NULL
    logger.info(paste("Tried to access Movebank for 30 minutes, no successful response. Movebank seems to be currently down. Try again later. Returning NULL. Original error:", geterrmessage()))
  }
  
  return(result)
}
