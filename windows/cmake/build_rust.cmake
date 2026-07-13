if(NOT DEFINED RUST_PROJECT_DIR OR RUST_PROJECT_DIR STREQUAL "")
  message(FATAL_ERROR "RUST_PROJECT_DIR is required")
endif()

if(NOT EXISTS "${RUST_PROJECT_DIR}/Cargo.toml")
  message(FATAL_ERROR "Rust manifest not found: ${RUST_PROJECT_DIR}/Cargo.toml")
endif()

if(NOT EXISTS "${RUST_PROJECT_DIR}/Cargo.lock")
  message(FATAL_ERROR "Rust lockfile not found: ${RUST_PROJECT_DIR}/Cargo.lock")
endif()

find_program(CARGO_EXECUTABLE NAMES cargo.exe cargo)
if(NOT CARGO_EXECUTABLE)
  message(FATAL_ERROR "Cargo was not found on PATH")
endif()

set(CARGO_BUILD_ARGS build --locked --lib)
if(NOT BUILD_CONFIG STREQUAL "Debug")
  list(APPEND CARGO_BUILD_ARGS --release)
  set(RUST_PROFILE release)
else()
  set(RUST_PROFILE debug)
endif()

execute_process(
  COMMAND "${CARGO_EXECUTABLE}" ${CARGO_BUILD_ARGS}
  WORKING_DIRECTORY "${RUST_PROJECT_DIR}"
  RESULT_VARIABLE CARGO_RESULT
)

if(NOT CARGO_RESULT EQUAL 0)
  message(FATAL_ERROR "Cargo failed with exit code ${CARGO_RESULT}")
endif()

set(RUST_CORE_DLL
  "${RUST_PROJECT_DIR}/target/${RUST_PROFILE}/openlogtool_core.dll")
if(NOT EXISTS "${RUST_CORE_DLL}")
  message(FATAL_ERROR "Cargo succeeded but did not produce ${RUST_CORE_DLL}")
endif()
