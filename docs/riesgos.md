# Riesgos y límites

## Matriz operativa

| Riesgo | Señal disponible | Control operativo |
| --- | --- | --- |
| Feed vencido o fuera de banda | `get_price` revierte; `get_feed` expone edad y límites | Suspender operación, verificar publicador y actualizar solo tras revisión |
| Deriva de pesos | Lentes y `allocation_report` | Comparar con mandato y planificar rebalanceo autorizado |
| Concentración | Indicador cuadrático en `allocation_report` | Definir límites externos de cartera y revisar cambios estructurales |
| Pérdida bajo escenario | `scenario_nav` | Ejecutar varios choques plausibles y contrastar con liquidez real |
| Clave operativa comprometida | Cambios de roles, feeds o parámetros | Custodia segregada, supervisión de eventos y rotación por owner |
| Activo ERC-20 no estándar | Fallos de transferencia o discrepancia de balances | Prueba de integración previa y política de admisión de activos |

## Límites de las métricas

Las métricas de analítica no predicen ejecución: no incluyen gas, comisiones de mercado, profundidad, slippage, correlación dinámica ni latencia de oráculos. Un descenso modelado de 350 bps significa únicamente que el escenario suministrado reduce el NAV calculado en 3,5 % respecto al valor inicial. No equivale a pérdida realizada. El usuario del contrato debe decidir y documentar el origen de los valores y los choques.

El alcance de los tests es local y determinista. La presencia de una pausa, monitor o política independiente no significa que todos los caminos del vault estén gobernados por ese componente. La revisión de una integración real debe mapear explícitamente llamadas, permisos, tokens, feeds y red de destino.
