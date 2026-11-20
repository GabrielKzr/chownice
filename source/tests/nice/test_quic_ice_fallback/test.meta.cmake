set(TEST_EXTRA_LIBS ossl_quic ice_udp_transport)
set(TEST_EXTRA_DEFINES ICE_TEST_FALLBACK)

if(BUILD_TESTING AND BUILD_NETWORK_TESTS)
    check_deps(DEPENDENCIES turnserver python3)
endif()

set_target_properties(test_quic_ice_fallback PROPERTIES
    PATCHBAY_MODE tcp
    PATCHBAY_TIMEOUT 75
    PATCHBAY_TEST_NAME network_quic_ice_fallback_tcp
    PATCHBAY_LABELS "network;nice;ice;quic;tcp;turn;fallback"
    PATCHBAY_ISP_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/../test_ice_udp_transport_turn/isp.sh"
    PATCHBAY_NAT_PROFILES "peer_a=Strict;peer_b=Strict"
)
