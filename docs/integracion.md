# Integración

## Preparación

1. Despliega los ERC-20 compatibles, el token `NIX` y el oráculo.
2. Configura cada feed con banda de precios y plazo de vigencia; publica un precio dentro de esa banda.
3. Despliega la bóveda con direcciones de `NIX`, oráculo y tesorería; asigna la bóveda en `NovaraIndexToken.set_vault`.
4. Registra los componentes con pesos que sumen 10 000 bps. Define límites y custodios de `owner`, `keeper` y `guardian` antes de exponer operaciones a usuarios.
5. Comprueba `component_count`, `component_at`, `get_component` y `total_assets` en la red de destino antes de enviar una emisión.

## Flujo de emisión

El cliente debe construir los arrays de tokens y cantidades en el orden que devuelve `component_at(i)` y aprobar cada ERC-20 para la bóveda. Puede usar `preview_mint(tokens, amounts)` para calcular participaciones brutas indicativas y fijar `_min_shares` con margen apropiado. La ejecución final es `mint(tokens, amounts, min_shares, receiver)`. La vista no reserva precio ni estado: una transacción posterior puede observar parámetros diferentes.

```text
tokens  = [nUSD, nETH, nBTC]
amounts = [50_000e18, 15e18, 0.5e18]
preview_mint(tokens, amounts) -> 100_000e18
mint(tokens, amounts, 99_900e18, receiver)
```

El ejemplo asume cesta vacía, precios 1/2 000/40 000, tolerancia suficiente y comisiones cero. En código cliente se deben usar enteros, no números flotantes. Un `0.5e18` mostrado aquí representa el entero `500000000000000000`.

## Flujo de salida

`preview_redeem(shares)` devuelve tokens, cantidades y valor estimado. El usuario envía `redeem(shares, min_value, receiver)` y recibe los componentes elegibles según balances y supply en el bloque de ejecución. No hay conversión automática a un único activo. Al integrar un token con transferencias no estándar, valida primero su compatibilidad en un entorno controlado.

## Errores frecuentes

- `TOKEN_ORDER` o `COMPONENT_LENGTH`: arrays desalineados respecto al registro.
- `COMPOSITION`: valor por activo fuera de la tolerancia de peso configurada.
- `STALE_PRICE`, `HIGH_PRICE` o `LOW_PRICE`: feed vencido o fuera de banda.
- `MIN_SHARES` o `MIN_VALUE`: protección del usuario no satisfecha.
- `COMPONENT_PAUSED`: una pausa administrativa afecta al flujo solicitado.

La integración debe tratar cada revert como un resultado de estado y volver a consultar el registro, supply y feeds; no debe ampliar automáticamente los límites de deslizamiento.
