cmake_minimum_required(VERSION 3.16)
project(chownice C)

include(CTest)
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake_modules/common_functions.cmake")

option(BUILD_NETWORK_TESTS "Build Patchbay network regression tests (Linux and Rust required)" OFF)

option(BUILD_THESIS "Enable the thesis PDF target (requires Tectonic)" OFF)
option(THESIS_ONLY "Configure only the thesis PDF target" OFF)

if(THESIS_ONLY AND NOT BUILD_THESIS)
    message(FATAL_ERROR "THESIS_ONLY requires BUILD_THESIS=ON")
endif()

if(BUILD_THESIS)
    find_program(TECTONIC_EXECUTABLE NAMES tectonic)
    if(NOT TECTONIC_EXECUTABLE)
        message(FATAL_ERROR "BUILD_THESIS requires Tectonic; install it or set TECTONIC_EXECUTABLE")
    endif()
    set(THESIS_BUILD_DIR "${CMAKE_BINARY_DIR}/thesis-source")
    add_custom_target(thesis_pdf
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${THESIS_BUILD_DIR}"
        COMMAND "${CMAKE_COMMAND}" -E copy_directory
                "${CMAKE_CURRENT_SOURCE_DIR}/docs/text" "${THESIS_BUILD_DIR}"
        COMMAND "${CMAKE_COMMAND}" -E chdir "${THESIS_BUILD_DIR}"
                "${TECTONIC_EXECUTABLE}" --outdir "${CMAKE_BINARY_DIR}" main.tex
        BYPRODUCTS "${CMAKE_BINARY_DIR}/main.pdf"
        COMMENT "Building thesis PDF"
        VERBATIM
    )
endif()

if(THESIS_ONLY)
    return()
endif()

if(BUILD_NETWORK_TESTS)
    if(DEFINED TEST_NAME AND NOT "${TEST_NAME}" STREQUAL "")
        message(FATAL_ERROR "BUILD_NETWORK_TESTS requires all peer targets; omit TEST_NAME")
    endif()
    set(BUILD_WEBRTC_TESTS ON)
endif()

if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()
option(BUILD_PCAP_TOOLS "Build namespace-compatible tcpdump and libpcap" OFF)
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake_modules/openssl.cmake")
if(BUILD_PCAP_TOOLS)
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake_modules/pcap.cmake")
endif()

add_subdirectory(source)

if(BUILD_NETWORK_TESTS)
    add_subdirectory(sim/patchbay)
endif()
