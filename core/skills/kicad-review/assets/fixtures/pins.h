/* Flat firmware pin header for scripts/selftest.sh, in the shape of aquila's app_config.h: one
 * `#define PIN_* <int>` per line. Paired with board.net, a trimmed kicad-cli 10.0.5 netlist of aquila-fc. */
#pragma once

#define PIN_MOTOR_FR      4   /* IO4_4: pad equals GPIO */
#define PIN_I2C_SDA       8   /* IO8_12: pad 12, the _<pad> suffix is not the GPIO */
#define PIN_BUZZER       17   /* IO17_10 */
#define PIN_USB_DN       19   /* USB_D-_13: built-in alias */
#define PIN_USB_DP       20   /* USB_D+_14 */
#define PIN_UART0_TX     43   /* TXD0_37 */
#define PIN_UART0_RX     44   /* RXD0_36 */
