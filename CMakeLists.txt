cmake_minimum_required(VERSION 3.24)
project(cppnativeexample LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(SERVICEGEN_USE_CCACHE "Use ccache when it is available" ON)
if(SERVICEGEN_USE_CCACHE AND NOT CMAKE_CXX_COMPILER_LAUNCHER)
  find_program(SERVICEGEN_CCACHE_PROGRAM ccache)
  if(SERVICEGEN_CCACHE_PROGRAM)
    set(CMAKE_CXX_COMPILER_LAUNCHER "${SERVICEGEN_CCACHE_PROGRAM}")
    message(STATUS "C++ compiler cache: ${SERVICEGEN_CCACHE_PROGRAM}")
  endif()
endif()
set(USERVER_SOURCE_DIR "/opt/userver" CACHE PATH "userver source checkout")

set(USERVER_FEATURE_GRPC ON CACHE BOOL "" FORCE)
set(USERVER_FORCE_DOWNLOAD_GRPC OFF CACHE BOOL "" FORCE)
set(USERVER_FORCE_DOWNLOAD_PROTOBUF OFF CACHE BOOL "" FORCE)
set(USERVER_FEATURE_OTLP OFF CACHE BOOL "" FORCE)
set(USERVER_FEATURE_CHAOTIC_EXPERIMENTAL OFF CACHE BOOL "" FORCE)
add_subdirectory("${USERVER_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/userver" EXCLUDE_FROM_ALL)
userver_setup_environment()
list(APPEND CMAKE_MODULE_PATH "${USERVER_SOURCE_DIR}/cmake")
include(UserverGrpcTargets)

set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
userver_add_grpc_library(native_inventory_api
    SOURCE_PATH "${CMAKE_CURRENT_SOURCE_DIR}"
    OUTPUT_PATH "${GENERATED_DIR}"
    PROTOS
      proto/inventoryserviceapi.proto
      proto/processorderitem.proto)

add_executable(inventoryservice src/inventoryservice.cpp)
target_link_libraries(inventoryservice PRIVATE userver-core userver-grpc native_inventory_api)

add_executable(orderservice src/orderservice.cpp)
target_link_libraries(orderservice PRIVATE userver-core userver-grpc native_inventory_api)
