# You can control your local app development via environment variables.
# You can define things like input-data, app-configuration etc.
# Per default your environment is defined in `/.env`

args <- configuration()
dotenv::load_dot_env("myPersonalPasswords.env")

args$username <- Sys.getenv("MOVEBANK_USERNAME")
args$password <- Sys.getenv("MOVEBANK_PASSWORD")

jsonlite::write_json(args, "app-configuration.json", auto_unbox = TRUE, pretty = TRUE)
                     

# This loads and installs the MoveApps R SDK
remotes::install_github("movestore/moveapps-sdk-r-package")
moveapps::logger.init()
moveapps::clearRecentOutput()

library("moveapps")
Sys.setenv(tz="UTC")
# `./RFunction.R` is the home of your app code
# It is the only file which will be bundled into the final app on MoveApps
source("RFunction.R")

# Lets simulate running your app on MoveApps
moveapps::runMoveAppsApp()
