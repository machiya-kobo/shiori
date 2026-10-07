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
configure_file(resources/balloons.r ${CMAKE_CURRENT_BINARY_DIR}/balloons.r COPYONLY)
list(APPEND REZ_INCLUDE_PATH ${CMAKE_CURRENT_BINARY_DIR})

set(SHIORI_SOURCES
    app/main.c
    app/net.c
    app/fetch.c
    app/draw.c
    app/resultlist.c
    app/searchwin.c
    app/reader.c
    app/prefs.c
    app/theme.c
    app/ae.c
    core/json.c
    core/http.c
    core/query.c
    core/results.c
    core/config.c
    core/roman.c
    core/notetext.c
)

# The desk accessory: a flat code resource (its DRVR header comes first, in
# .rsrcheader), then a 'DRVR' resource. It shares the core and the app's
# fetch, MacTCP, preferences, drawing and theme code; -gc-sections keeps only
# what it calls (its _start names the header, so the header stays). A DA must
# stay under 32 KB.
add_executable(ShioriDA da/ShioriDA.c da/sendread.c
    core/json.c core/http.c core/query.c core/results.c core/config.c core/roman.c core/notetext.c
    app/fetch.c app/net.c app/prefs.c app/draw.c app/theme.c)
set_target_properties(ShioriDA PROPERTIES OUTPUT_NAME ShioriDA.flt LINK_FLAGS "-Wl,--mac-flat -Wl,-gc-sections -Wl,--undefined=da_header")
target_compile_options(ShioriDA PRIVATE -m68000 -Os -Wall -Wno-unused-parameter -ffunction-sections -fdata-sections)
foreach(v SHIORI_DEFAULT_HISTER SHIORI_DEFAULT_KURA SHIORI_DEFAULT_TOKEN)
    if(${v})
        target_compile_definitions(ShioriDA PRIVATE ${v}="${${v}}")
    endif()
endforeach()
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/ShioriDA.rsrc.bin
    COMMAND ${REZ} ${CMAKE_CURRENT_SOURCE_DIR}/da/ShioriDA.r -o ShioriDA.rsrc.bin
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ShioriDA ${CMAKE_CURRENT_SOURCE_DIR}/da/ShioriDA.r)

# The DA on its own, to install: a Font/DA Mover suitcase ('dfil', 'DMOV').
# System 6 installs it with Font/DA Mover; System 7's Finder opens it, and the
# DA can be dragged out to the System Folder (it then shows in every Apple menu).
add_custom_command(
    OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/Shiori Search.bin"
    COMMAND ${REZ} ${CMAKE_CURRENT_SOURCE_DIR}/da/ShioriDA.r -t dfil -c DMOV -o "Shiori Search.bin"
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ShioriDA ${CMAKE_CURRENT_SOURCE_DIR}/da/ShioriDA.r)
add_custom_target(ShioriSearchSuitcase ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/Shiori Search.bin")

# The app carries the DA in its own resources too, so Shiori's Apple menu
# opens it without installing anything.
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

# A System 7 test tool, never shipped: sends Shiori SHIO/read through the
# desk accessory's code (tests/aesend.c).
add_application(ShioriAESend tests/aesend.c da/sendread.c tests/aesend.r)
target_compile_options(ShioriAESend PRIVATE -m68000 -Os -Wall)
