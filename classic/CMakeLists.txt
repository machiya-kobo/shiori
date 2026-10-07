# Shiori for Classic Macintosh: built with Retro68 (scripts/build.sh).
cmake_minimum_required(VERSION 3.10)
project(Shiori C)

if(NOT DEFINED SHIORI_VERSION)
    set(SHIORI_VERSION "0.0.0-dev")
endif()
# The bridge and token until Preferences has them: from local.env through build.sh.
set(SHIORI_DEFAULT_HISTER "" CACHE STRING "the bridge's Hister address, http://host:8070/")
set(SHIORI_DEFAULT_KURA "" CACHE STRING "the bridge's Kura address, http://host:8071/")
set(SHIORI_DEFAULT_TOKEN "" CACHE STRING "the Mac's room token")

configure_file(resources/shiori.r.in ${CMAKE_CURRENT_BINARY_DIR}/shiori.r @ONLY)

set(SHIORI_SOURCES
    app/main.c
    app/net.c
    app/fetch.c
    app/draw.c
    app/resultlist.c
    app/searchwin.c
    app/reader.c
    core/json.c
    core/http.c
    core/query.c
    core/results.c
    core/config.c
    core/roman.c
    core/notetext.c
)

# The desk accessory: a flat code resource (its DRVR header comes first, in
# .rsrcheader), then a 'DRVR' resource. No -gc-sections: nothing references
# the header, and the linker would drop it.
add_executable(ShioriDA da/ShioriDA.c)
set_target_properties(ShioriDA PROPERTIES OUTPUT_NAME ShioriDA.flt LINK_FLAGS "-Wl,--mac-flat")
target_compile_options(ShioriDA PRIVATE -m68000 -Os -Wall -Wno-unused-parameter)
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/ShioriDA.rsrc.bin
    COMMAND ${REZ} ${CMAKE_CURRENT_SOURCE_DIR}/da/ShioriDA.r -I${REZ_INCLUDE_PATH} -o ShioriDA.rsrc.bin
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ShioriDA ${CMAKE_CURRENT_SOURCE_DIR}/da/ShioriDA.r)

# Phase 0 carries the DA in the app's own resources, so the app's Apple menu
# opens it (installing it in the System comes with phase 7).
add_application(Shiori CREATOR "SHIO" ${SHIORI_SOURCES} ${CMAKE_CURRENT_BINARY_DIR}/shiori.r
    ${CMAKE_CURRENT_BINARY_DIR}/ShioriDA.rsrc.bin)

target_compile_definitions(Shiori PRIVATE SHIORI_VERSION="${SHIORI_VERSION}")
foreach(v SHIORI_DEFAULT_HISTER SHIORI_DEFAULT_KURA SHIORI_DEFAULT_TOKEN)
    if(${v})
        target_compile_definitions(Shiori PRIVATE ${v}="${${v}}")
    endif()
endforeach()

# The 68000 (a Mac Plus), smallest code, no dead code.
target_compile_options(Shiori PRIVATE -m68000 -Os -Wall -Wextra -Wno-unused-parameter
    -ffunction-sections -fdata-sections)
set_target_properties(Shiori PROPERTIES LINK_FLAGS "-Wl,-gc-sections")
