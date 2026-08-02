# Machines reached through STM32Cube

Reserved. The peripheral handles this binding uses — `huart2`, `hi2c1`, `LD2_GPIO_Port`
and `LD2_Pin` — are still written into the binding's C++ directly, which holds only while
NUCLEO-F446RE is the one board here.

They move here the moment a second STM32 board arrives, because that is when `huart2`
stops being a fact about STM32Cube and becomes a fact about one board seen through it.
