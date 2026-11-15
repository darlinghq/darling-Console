project(Console)

# The sources rely on the modern Objective-C runtime (synthesized instance
# variables), which 32-bit Darwin does not have: only a 64-bit slice is built.
if (NOT BUILD_TARGET_64BIT)
	return()
endif ()

add_compile_options(
	-nostdinc
	-fobjc-arc
	-Wno-deprecated-declarations
)

add_darling_executable(Console
	Sources/AppDelegate.m
	Sources/LogEntry.m
	Sources/MainWindowController.m
	Sources/main.m
)

target_link_libraries(Console AppKit Foundation objc)

set(Console_contents "libexec/darling/Applications/Utilities/Console.app/Contents")

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/PkgInfo "APPL????")

install(TARGETS Console DESTINATION ${Console_contents}/MacOS)
install(FILES
		${CMAKE_CURRENT_SOURCE_DIR}/Info.plist
		${CMAKE_CURRENT_BINARY_DIR}/PkgInfo
	DESTINATION ${Console_contents})
