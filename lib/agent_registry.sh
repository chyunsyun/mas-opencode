#!/usr/bin/env bash

if [[ -z "${MAS_ROOT:-}" ]]; then
    MAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

agent_registry_agents() {
    printf '%s\n' director chief engineer1 engineer2 engineer3 auditor
}

agent_registry_engineers() {
    printf '%s\n' engineer1 engineer2 engineer3
}

agent_registry_role() {
    case "${1:-}" in
        director) echo "director" ;;
        chief) echo "chief" ;;
        engineer1|engineer2|engineer3) echo "engineer" ;;
        auditor) echo "auditor" ;;
        *) return 1 ;;
    esac
}

agent_registry_label() {
    case "${1:-}" in
        director) echo "部長" ;;
        chief) echo "係長" ;;
        engineer1) echo "エンジニア1" ;;
        engineer2) echo "エンジニア2" ;;
        engineer3) echo "エンジニア3" ;;
        auditor) echo "監査役" ;;
        *) return 1 ;;
    esac
}

agent_registry_is_engineer() {
    case "${1:-}" in
        engineer1|engineer2|engineer3) return 0 ;;
        *) return 1 ;;
    esac
}
