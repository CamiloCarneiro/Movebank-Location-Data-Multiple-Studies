# Multi-Study Movebank Download

MoveApps

Github repository: <https://github.com/CamiloCarneiro/Movebank-Location-Data-Multiple-Studies>

## Description

This app aims at downloading data from multiple studies at once, based on the user permission and access to the data (Collaborator, Data Manager, both, or all studies the user can download data from). The code was adapted from the [Movebank Location app](https://github.com/movestore/Movebank-Loc-move2), which only allows for a single study to be downloaded.

## Documentation

This app allows users to gather data from several studies in a swift way, in oposition to introducing an app per study in the pipeline (as is the case with [Movebank Location app](https://github.com/movestore/Movebank-Loc-move2)). However, with *Multi-Study Movebank Download* no specific animals can be selected, but all are automatically included (contrary to [Movebank Location app](https://github.com/movestore/Movebank-Loc-move2)). Furthermore, no specific studies can be selected, but rather all the user have download access, or all the user is a collaborator or a data manager on, or both.

The period of data to be downloaded can be defined, and types of sensors can be selected. Data thinning can be done, and a minimal set of variables can be selected.

### Application scope

#### Generality of App usability

This app was developed to help gather all data a user has access to, and therefore allow for overall data summaries or overviews of what is available to them.

[*Attention*]{.underline}: If all data with download permission are selected (particularly for a considerable period of time), the app may take a long time to finish and the volume of data returned may be too large to handle easily.

### Input type

*Example*: `move2::move2_loc`

### Output type

*Example:* `move2::move2_loc`

### Settings

`Movebank username and password` (username, password): user log in details to their Movebank account.

`Download Studies by Access Level` (study_access): defines which set of studies to download. (I) all studies where the user is a collaborator, (II) data manager, (III) both, or (IV) all studies where that data can be downloaded from (i.e., option III plus public domain studies).

`Select Sensors` (select_sensors): determines which sensor type(s) data to download. See the [list of sensor types here](https://github.com/movebank/movebank-api-doc/blob/master/movebank-api.md#get-a-list-of-sensor-types).

`Include Outliers` (incl_outliers): whether to include outliers (defined as such on Movebank).

`Use Minimal Arguments` (minarg): whether to download a minimal dataset, that includes only timestamp, track_id, location and the track attributes.

`Thinning Interval Value` (thin_numb): numeric value for thinning interval.

`Thinning Interval Unit` (thin_unit): unit for thinning interval: `minutes`, `hours` or `days`.

`Start Timestamp` (timestamp_start): start date-time for a defined period of time to download data.

`End Timestamp` (timestamp_end): end date-time for a defined period of time to download data.

`Last X Days` (lastXdays): download only the last X `days` of data. If set, it overrides the previous time window arguments.

### Changes in output data

The app filterers the input data as selected by the user.

### Most common errors

*to be described as the app is further used*

### Null or error handling

**`Username` and `Password`**: If either is missing or invalid, Movebank authentication fails. The App retries for up to 30 minutes and then returns `NULL` with a warning.

**`Select Sensors`**: If `NULL`, all available location sensors are downloaded. If provided in an incorrect format, sensor filtering may fail silently and all sensors may be downloaded.

**`Start` and `End Timestamp`**: If both are `NULL`, no time filtering is applied unless `lastXdays` is given. Invalid timestamp formats may cause downloads to fail and result in `NULL` after retries.

**`Last X Days`**: If set, it overrides `timestamp_start` and `timestamp_end`. Non-positive values may return empty results.

**`Download Studies by Access Level`**: If no studies match the selected access type, the App returns `NULL`.

**`Thinning` parameters**\
If `thin = TRUE` but thinning parameters are invalid, thinning fails and the App may return `NULL` after retries.

**Movebank access errors**\
If Movebank cannot be reached (e.g., service outage or rate limits), the App retries for up to 30 minutes. If still unsuccessful, it returns `NULL`.
