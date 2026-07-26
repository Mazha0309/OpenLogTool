use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, Data, DeriveInput, Fields, LitStr};

#[proc_macro_derive(FromRow, attributes(sqlx))]
pub fn derive_from_row(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let name = &input.ident;
    let generics = &input.generics;
    let (impl_generics, type_generics, where_clause) = generics.split_for_impl();

    let Data::Struct(data) = &input.data else {
        return syn::Error::new_spanned(name, "FromRow can only be derived for structs")
            .to_compile_error()
            .into();
    };
    let Fields::Named(fields) = &data.fields else {
        return syn::Error::new_spanned(name, "FromRow requires named fields")
            .to_compile_error()
            .into();
    };

    let assignments = fields.named.iter().map(|field| {
        let ident = field.ident.as_ref().expect("named field");
        let mut column = ident.to_string();
        if let Some(stripped) = column.strip_prefix("r#") {
            column = stripped.to_string();
        }

        for attribute in &field.attrs {
            if !attribute.path().is_ident("sqlx") {
                continue;
            }
            let result = attribute.parse_nested_meta(|meta| {
                if meta.path.is_ident("rename") {
                    let value = meta.value()?;
                    let literal: LitStr = value.parse()?;
                    column = literal.value();
                    Ok(())
                } else {
                    Err(meta.error("unsupported sqlx field attribute"))
                }
            });
            if let Err(error) = result {
                return error.to_compile_error();
            }
        }

        quote! {
            #ident: ::sqlx::Row::try_get(row, #column)?
        }
    });

    quote! {
        impl #impl_generics ::sqlx::FromRow for #name #type_generics #where_clause {
            fn from_row(
                row: &::sqlx::sqlite::SqliteRow,
            ) -> ::std::result::Result<Self, ::sqlx::Error> {
                Ok(Self {
                    #(#assignments,)*
                })
            }
        }
    }
    .into()
}
