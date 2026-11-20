set(TEST_EXTRA_LIBS ice_udp_transport)
set(TEST_EXTRA_DEFINES ICE_TEST_FALLBACK)

if(BUILD_TESTING AND BUILD_NETWORK_TESTS)
    check_deps(DEPENDENCIES turnserver python3)
endif()

set_target_properties(test_ice_udp_transport_fallback PROPERTIES
    PATCHBAY_MODE udp
    PATCHBAY_TIMEOUT 30
    PATCHBAY_TEST_NAME network_ice_udp_transport_fallback
    PATCHBAY_LABELS "network;nice;ice;turn;fallback"
    PATCHBAY_ISP_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/../test_ice_udp_transport_turn/isp.sh"
    PATCHBAY_NAT_PROFILES "peer_a=Strict;peer_b=Strict"
)
