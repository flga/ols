package server

import "core:odin/parser"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:fmt"
import "core:log"
import "core:strings"
import path "core:path/slashpath"
import "core:mem"
import "core:strconv"
import "core:path/filepath"
import "core:sort"
import "core:slice"
import "core:os"


import "shared:common"
import "shared:index"
import "shared:analysis"

get_definition_location :: proc(document: ^common.Document, position: common.Position) -> ([]common.Location, bool) {
	using analysis;

	locations := make([dynamic]common.Location, context.temp_allocator);

	location: common.Location;

	ast_context := make_ast_context(document.ast, document.imports, document.package_name, document.uri.uri, &document.symbol_cache);

	uri: string;

	position_context, ok := get_document_position_context(document, position, .Definition);

	if !ok {
		log.warn("Failed to get position context");
		return {}, false;
	}

	get_globals(document.ast, &ast_context);

	if position_context.function != nil {
		get_locals(document.ast, position_context.function, &ast_context, &position_context);
	}

	if position_context.selector != nil {

		//if the base selector is the client wants to go to.
		if base, ok := position_context.selector.derived.(ast.Ident); ok && position_context.identifier != nil {

			ident := position_context.identifier.derived.(ast.Ident);

			if ident.name == base.name {

				if resolved, ok := resolve_location_identifier(&ast_context, ident); ok {
					location.range = resolved.range;

					if resolved.uri == "" {
						location.uri = document.uri.uri;
					} else {
						location.uri = resolved.uri;
					}

					append(&locations, location);

					return locations[:], true;
				} else {
					return {}, false;
				}
			}
		}

		//otherwise it's the field the client wants to go to.

		selector: index.Symbol;

		ast_context.use_locals = true;
		ast_context.use_globals = true;
		ast_context.current_package = ast_context.document_package;

		selector, ok = resolve_type_expression(&ast_context, position_context.selector);

		if !ok {
			return {}, false;
		}

		field: string;

		if position_context.field != nil {

			switch v in position_context.field.derived {
			case ast.Ident:
				field = v.name;
			}
		}

		uri = selector.uri;

		#partial switch v in selector.value {
		case index.SymbolEnumValue:
			location.range = selector.range;
		case index.SymbolStructValue:
			for name, i in v.names {
				if strings.compare(name, field) == 0 {
					location.range = common.get_token_range(v.types[i]^, document.ast.src);
				}
			}
		case index.SymbolPackageValue:
			if symbol, ok := index.lookup(field, selector.pkg); ok {
				location.range = symbol.range;
				uri = symbol.uri;
			} else {
				return {}, false;
			}
		}

		if !ok {
			return {}, false;
		}
	} else if position_context.identifier != nil {

		if resolved, ok := resolve_location_identifier(&ast_context, position_context.identifier.derived.(ast.Ident)); ok {
			location.range = resolved.range;
			uri = resolved.uri;
		} else {
			return {}, false;
		}
	} else {
		return {}, false;
	}

	//if the symbol is generated by the ast we don't set the uri.
	if uri == "" {
		location.uri = document.uri.uri;
	} else {
		location.uri = uri;
	}

	append(&locations, location)

	return locations[:], true;
}