#!/usr/bin/env hbrun
/*
 * Recalculate SRI hashes for assets.json
 *
 * Copyright 2017 Viktor Szakats (vszakats.net/harbour)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA (or visit
 * their website at https://www.gnu.org/).
 *
 */

/* Requires: curl */

procedure main( fn )

  local r, pkg, file, url, body, conf, old

  fn := hb_defaultvalue( fn, 'hbdoc_assets.yml' )

  for each pkg in r := hb_yaml_decode( conf := hb_memoread( fn ) )
    for each file in pkg[ 'files' ]
      ? url := ;
        pkg[ 'root' ] + ;
        iif( 'ver' $ pkg, pkg[ 'ver' ] + '/', '' ) + ;
        file[ 'name' ]
      body := dl( url )
      if 'sri' $ file
        old := file[ 'sri' ]
        file[ 'sri' ] := 'sha384-' + hb_base64encode( hb_sha384( body, .t. ) )
        conf := StrTran( conf, old, file[ 'sri' ] )  /* sloppy hack */
      endif
    next
  next

  hb_memowrit( fn, conf )

  return

static function dl( url )

  local stdout

  hb_processrun( hb_strformat( 'curl -fsS -L --proto-redir =https "%1$s"', url ),, @stdout )

  return stdout
