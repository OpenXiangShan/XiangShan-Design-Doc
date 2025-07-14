# Replacer Submodule Documentation

The PLRU replacement algorithm is employed. Considering that each fetch may
access consecutive doublelines, two replacers are set up for odd and even
addresses, updating the respective replacer during touch and victim operations
based on address parity.

![PLRU Algorithm Illustration](../figure/ICache/Replacer/plru.png)

## touch

The Replacer has two touch ports to support dual-line access, with touch
operations distributed to the corresponding replacer based on the odd/even
address.

## victim

The Replacer has only one victim port because only one MSHR writes to the SRAM
at a time, similarly retrieving the waymask from the corresponding replacer
based on the address parity. The touch operation to update the replacer is
performed in the next cycle.
