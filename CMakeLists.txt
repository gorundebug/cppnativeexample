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
find_package(userver CONFIG REQUIRED COMPONENTS core grpc)
include(UserverGrpcTargets)

set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
userver_add_grpc_library(native_inventory_api
    SOURCE_PATH "${CMAKE_CURRENT_SOURCE_DIR}"
    OUTPUT_PATH "${GENERATED_DIR}"
    PROTOS
      proto/inventoryserviceapi.proto
      proto/processorderitem.proto)

add_executable(inventoryservice src/inventoryservice.cpp)
target_link_libraries(inventoryservice PRIVATE userver::core userver::grpc native_inventory_api)

add_executable(orderservice src/orderservice.cpp)
target_link_libraries(orderservice PRIVATE userver::core userver::grpc native_inventory_api)
