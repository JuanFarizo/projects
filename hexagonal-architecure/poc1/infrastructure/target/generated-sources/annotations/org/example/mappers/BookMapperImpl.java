package org.example.mappers;

import java.util.ArrayList;
import java.util.List;
import javax.annotation.processing.Generated;
import org.example.data.BookDto;
import org.example.data.BookDto.BookDtoBuilder;
import org.example.entity.Book;
import org.example.entity.Book.BookBuilder;

@Generated(
    value = "org.mapstruct.ap.MappingProcessor",
    date = "2026-08-31T09:08:00-0300",
    comments = "version: 1.4.2.Final, compiler: Eclipse JDT (IDE) 3.46.100.v20260624-0231, environment: Java 25.0.2 (Amazon.com Inc.)"
)
public class BookMapperImpl implements BookMapper {

    @Override
    public BookDto bookToBookDto(Book book) {
        if ( book == null ) {
            return null;
        }

        BookDtoBuilder bookDto = BookDto.builder();

        bookDto.id( book.getId() );
        bookDto.title( book.getTitle() );
        bookDto.description( book.getDescription() );
        bookDto.price( book.getPrice() );

        return bookDto.build();
    }

    @Override
    public Book bookDtoToBook(BookDto bookDto) {
        if ( bookDto == null ) {
            return null;
        }

        BookBuilder book = Book.builder();

        book.description( bookDto.getDescription() );
        book.id( bookDto.getId() );
        book.price( bookDto.getPrice() );
        book.title( bookDto.getTitle() );

        return book.build();
    }

    @Override
    public List<BookDto> bookListToBookDtoList(List<Book> bookList) {
        if ( bookList == null ) {
            return null;
        }

        List<BookDto> list = new ArrayList<BookDto>( bookList.size() );
        for ( Book book : bookList ) {
            list.add( bookToBookDto( book ) );
        }

        return list;
    }

    @Override
    public List<Book> bookDtoListTobookList(List<BookDto> BookDtoList) {
        if ( BookDtoList == null ) {
            return null;
        }

        List<Book> list = new ArrayList<Book>( BookDtoList.size() );
        for ( BookDto bookDto : BookDtoList ) {
            list.add( bookDtoToBook( bookDto ) );
        }

        return list;
    }
}
