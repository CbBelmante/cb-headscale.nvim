#!/bin/bash
# Testa se o terminal suporta OSC 66 text sizing
echo ""
echo "=== Teste OSC 66 Text Sizing ==="
echo ""
echo "Texto normal:"
echo "Hello World"
echo ""
echo "s=2 (double):"
printf '\e]66;s=2;Hello World\a'
echo ""
echo ""
echo ""
echo "s=3 (triple):"
printf '\e]66;s=3;Hello World\a'
echo ""
echo ""
echo ""
echo ""
echo "Se voce viu texto MAIOR acima, OSC 66 funciona!"
echo "Se viu texto normal ou lixo, nao suporta."
