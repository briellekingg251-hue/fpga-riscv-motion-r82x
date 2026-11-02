/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Mapper support query against InfoNES's own table, so the ROM list can grey
 * out cartridges before InfoNES_Reset would reject them. */
#include "InfoNES.h"
#include "InfoNES_Mapper.h"
#include "nes_port.h"

int nes_mapper_supported(unsigned mapper)
{
    for (const struct MapperTable_tag *m = MapperTable; m->nMapperNo != -1; ++m)
        if ((unsigned)m->nMapperNo == mapper) return 1;
    return 0;
}
